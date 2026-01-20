#!/bin/bash
# Archives and uploads existing incremental backup files to a simulated S3 bucket.

set -euo pipefail

# --- Configuration from JSON file ---
CONFIG_FILE="/etc/backup/config.json"
ENCRYPTION_KEY_FILE="/etc/backup/backup.key" # Path to the encryption key

# --- Logging ---
# This function will be defined after LOG_FILE is sourced from config
log_message() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Check for required tools
for tool in jq aws openssl; do
    if ! command -v $tool &> /dev/null; then
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: Required tool '$tool' is not installed or in PATH."
        exit 1
    fi
done

# Check for config file
if [ ! -f "$CONFIG_FILE" ]; then
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: Backup configuration file not found at $CONFIG_FILE"
  exit 1
fi

# Source configuration from JSON
S3_BUCKET_NAME=$(jq -r '.s3_bucket_name' "$CONFIG_FILE")
BACKUP_BACKEND=$(jq -r '.backup_backend // "s3"' "$CONFIG_FILE")
CASSANDRA_DATA_DIR=$(jq -r '.cassandra_data_dir' "$CONFIG_FILE")
LOG_FILE=$(jq -r '.incremental_backup_log_file' "$CONFIG_FILE")
LISTEN_ADDRESS=$(jq -r '.listen_address' "$CONFIG_FILE")


# Validate sourced config
if [ -z "$S3_BUCKET_NAME" ] || [ -z "$CASSANDRA_DATA_DIR" ] || [ -z "$LOG_FILE" ]; then
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: One or more required configuration values are missing from $CONFIG_FILE"
  exit 1
fi

# --- Static Configuration ---
BACKUP_TAG=$(date +'%Y-%m-%d-%H-%M') # NEW timestamp format
HOSTNAME=$(hostname -s)
BACKUP_TEMP_DIR="/tmp/cassandra_backups_$$" # Use PID to ensure uniqueness


# --- Cleanup Functions ---
cleanup_temp_dir() {
  if [ -d "$BACKUP_TEMP_DIR" ]; then
    log_message "Cleaning up temporary directory: $BACKUP_TEMP_DIR"
    rm -rf "$BACKUP_TEMP_DIR"
  fi
}

# --- Main Logic ---
if [ "$(id -u)" -ne 0 ]; then
  log_message "ERROR: This script must be run as root."
  exit 1
fi

trap cleanup_temp_dir EXIT

# Check for global backup disable flag
if [ -f "/var/lib/backup-disabled" ]; then
    log_message "INFO: Backup is disabled via /var/lib/backup-disabled. Aborting."
    exit 0
fi

# Check for encryption key
if [ ! -r "$ENCRYPTION_KEY_FILE" ]; then
    log_message "ERROR: Encryption key not found or not readable at $ENCRYPTION_KEY_FILE"
    exit 1
fi

log_message "--- Starting Granular Incremental Cassandra Backup Process ---"
log_message "S3 Bucket: $S3_BUCKET_NAME"
log_message "Backup Timestamp (Tag): $BACKUP_TAG"

# Find all incremental backup directories that are not empty
# This finds any 'backups' directory with at least one file, then returns the directory name
INCREMENTAL_DIRS=$(find "$CASSANDRA_DATA_DIR" -type d -name "backups" -not -empty -print)

if [ -z "$INCREMENTAL_DIRS" ]; then
    log_message "No new incremental backup files found. Nothing to do."
    exit 0
fi

# Create manifest and temp dir
mkdir -p "$BACKUP_TEMP_DIR"
MANIFEST_FILE="$BACKUP_TEMP_DIR/backup_manifest.json"

UPLOAD_ERRORS=0
TABLES_BACKED_UP="[]"
SYSTEM_KEYSPACES="system system_auth system_distributed system_schema system_traces system_views system_virtual_schema dse_system dse_perf dse_security solr_admin"

# Loop through each directory containing incremental backups
echo "$INCREMENTAL_DIRS" | while read -r backup_dir; do
    # Path is like: /var/lib/cassandra/data/my_ks/my_table-uuid/backups
    relative_path=${backup_dir#$CASSANDRA_DATA_DIR/}
    ks_name=$(echo "$relative_path" | cut -d'/' -f1)

    # Skip system keyspaces
    if [[ $SYSTEM_KEYSPACES =~ $ks_name ]]; then
        continue
    fi
    
    table_dir_name=$(echo "$relative_path" | cut -d'/' -f2)
    table_name=$(echo "$table_dir_name" | cut -d'-' -f1)
    
    log_message "Processing incremental backup for: $ks_name.$table_name"
    
    s3_path="s3://$S3_BUCKET_NAME/$HOSTNAME/$BACKUP_TAG/$ks_name/$table_name/incremental.tar.enc"
    
    # Streaming pipeline: tar -> gzip -> openssl -> aws s3
    tar -C "$backup_dir" -c . | \
    gzip | \
    openssl enc -aes-256-cbc -salt -pass "file:$ENCRYPTION_KEY_FILE" | \
    aws s3 cp - "$s3_path"

    # Check the exit code of the aws cli command (the last in the pipe)
    if [ ${PIPESTATUS[3]} -eq 0 ]; then
        log_message "Successfully uploaded incremental backup for $ks_name.$table_name"
        TABLES_BACKED_UP=$(echo "$TABLES_BACKED_UP" | jq ". + [\"$ks_name.$table_name\"]")
        
        # After success, clean up the source files
        log_message "Cleaning up local incremental files for $ks_name.$table_name"
        rm -f "$backup_dir"/*
    else
        log_message "ERROR: Failed to upload incremental backup for $ks_name.$table_name. Local files will not be deleted."
        UPLOAD_ERRORS=$((UPLOAD_ERRORS + 1))
    fi
done

if [ "$UPLOAD_ERRORS" -gt 0 ]; then
    log_message "ERROR: $UPLOAD_ERRORS incremental backup(s) failed to upload. The backup is incomplete."
    # We still upload a manifest so the operator knows what *did* succeed.
fi


# Create and Upload Manifest
log_message "Creating backup manifest at $MANIFEST_FILE..."

CLUSTER_NAME=$(nodetool describecluster | grep 'Name:' | awk '{print $2}')

if [ -n "$LISTEN_ADDRESS" ]; then
    NODE_IP="$LISTEN_ADDRESS"
else
    NODE_IP="$(hostname -i)"
fi

NODE_STATUS_LINE=$(nodetool status | grep "\b$NODE_IP\b" || echo "Unknown UNKNOWN $LISTEN_ADDRESS UNKNOWN UNKNOWN UNKNOWN")
NODE_DC=$(echo "$NODE_STATUS_LINE" | awk '{print $5}')
NODE_RACK=$(echo "$NODE_STATUS_LINE" | awk '{print $6}')

jq -n \
  --arg cluster_name "$CLUSTER_NAME" \
  --arg backup_id "$BACKUP_TAG" \
  --arg backup_type "incremental" \
  --arg timestamp "$(date --iso-8601=seconds)" \
  --arg node_ip "$NODE_IP" \
  --arg node_dc "$NODE_DC" \
  --arg node_rack "$NODE_RACK" \
  --argjson tables "$TABLES_BACKED_UP" \
  '{
    "cluster_name": $cluster_name,
    "backup_id": $backup_id,
    "backup_type": $backup_type,
    "timestamp_utc": $timestamp,
    "source_node": {
      "ip_address": $node_ip,
      "datacenter": $node_dc,
      "rack": $node_rack
    },
    "tables_backed_up": $tables
  }' > "$MANIFEST_FILE"

if [ -f "/var/lib/upload-disabled" ]; then
    log_message "INFO: S3 upload is disabled. Manifest and backups are local."
else
    if [ "$BACKUP_BACKEND" == "s3" ]; then
        log_message "Uploading manifest file..."
        MANIFEST_S3_PATH="s3://$S3_BUCKET_NAME/$HOSTNAME/$BACKUP_TAG/backup_manifest.json"
        if ! aws s3 cp "$MANIFEST_FILE" "$MANIFEST_S3_PATH"; then
            log_message "ERROR: Failed to upload manifest to S3. The backup is not properly indexed."
            # Don't exit, still report final status
        else
            log_message "Manifest uploaded successfully."
        fi
    fi
fi

if [ "$UPLOAD_ERRORS" -gt 0 ]; then
    log_message "--- Granular Incremental Backup Process Finished with ERRORS ---"
    exit 1
else
    log_message "--- Granular Incremental Backup Process Finished Successfully ---"
fi

exit 0
