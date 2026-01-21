#!/bin/bash
# Archives and uploads existing incremental backup files to a simulated S3 bucket.

set -euo pipefail

# This script needs to run with /bin/bash to support PIPESTATUS
if [ -z "$BASH_VERSION" ]; then
    exec /bin/bash "$0" "$@"
fi

# --- Configuration from JSON file ---
CONFIG_FILE="/etc/backup/config.json"

# --- Logging ---
# This function will be defined after LOG_FILE is sourced from config
log_message() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Check for required tools
for tool in jq aws openssl nodetool; do
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
UPLOAD_STREAMING=$(jq -r '.upload_streaming // "false"' "$CONFIG_FILE")


# Validate sourced config
if [ -z "$S3_BUCKET_NAME" ] || [ -z "$CASSANDRA_DATA_DIR" ] || [ -z "$LOG_FILE" ]; then
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: One or more required configuration values are missing from $CONFIG_FILE"
  exit 1
fi

# --- Static Configuration ---
BACKUP_TAG=$(date +'%Y-%m-%d-%H-%M')
HOSTNAME=$(hostname -s)
BACKUP_TEMP_DIR="/tmp/cassandra_backups_$$"
LOCK_FILE="/var/run/cassandra_backup.lock"


# --- AWS Credential Check Function ---
check_aws_credentials() {
  # Skip check if backend isn't S3 or if uploads are disabled via flag file
  if [ "$BACKUP_BACKEND" != "s3" ] || [ -f "/var/lib/upload-disabled" ]; then
    return 0
  fi
  
  log_message "INFO: Verifying AWS credentials..."
  if ! aws sts get-caller-identity > /dev/null 2>&1; then
    log_message "ERROR: AWS credentials not found or invalid."
    log_message "Please configure credentials for this node, e.g., via an IAM role."
    log_message "Aborting backup."
    return 1
  fi
  log_message "INFO: AWS credentials are valid."
  return 0
}


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

# Pre-flight checks before creating a lock or doing any work
if [ -f "/var/lib/backup-disabled" ]; then
    log_message "INFO: Backup is disabled via /var/lib/backup-disabled. Aborting."
    exit 0
fi

if ! check_aws_credentials; then
    exit 1
fi


if [ -f "$LOCK_FILE" ]; then
    log_message "Lock file $LOCK_FILE exists. Checking if process is running..."
    OLD_PID=$(cat "$LOCK_FILE")
    if ps -p "$OLD_PID" > /dev/null; then
        log_message "Backup process with PID $OLD_PID is still running. Exiting."
        exit 1
    else
        log_message "Stale lock file found for dead PID $OLD_PID. Removing."
        rm -f "$LOCK_FILE"
    fi
fi


# Create a temporary file for the encryption key
TMP_KEY_FILE=$(mktemp)
chmod 600 "$TMP_KEY_FILE"

# Create lock file and set combined trap for all cleanup actions
echo $$ > "$LOCK_FILE"
trap 'rm -f "$LOCK_FILE"; rm -f "$TMP_KEY_FILE"; cleanup_temp_dir' EXIT


# Extract key from config and write to temp file
ENCRYPTION_KEY=$(jq -r '.encryption_key' "$CONFIG_FILE")
if [ -z "$ENCRYPTION_KEY" ] || [ "$ENCRYPTION_KEY" == "null" ]; then
    log_message "ERROR: encryption_key is empty or not found in $CONFIG_FILE"
    exit 1
fi
echo -n "$ENCRYPTION_KEY" > "$TMP_KEY_FILE"


log_message "--- Starting Granular Incremental Cassandra Backup Process ---"
log_message "S3 Bucket: $S3_BUCKET_NAME"
log_message "Backup Timestamp (Tag): $BACKUP_TAG"
log_message "Streaming Mode: $UPLOAD_STREAMING"


# Find all incremental backup directories that are not empty
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
    relative_path=${backup_dir#$CASSANDRA_DATA_DIR/}
    ks_name=$(echo "$relative_path" | cut -d'/' -f1)

    if [[ " $SYSTEM_KEYSPACES " =~ " $ks_name " ]]; then
        continue
    fi
    
    table_dir_name=$(echo "$relative_path" | cut -d'/' -f2)
    table_name=$(echo "$table_dir_name" | cut -d'-' -f1)
    
    log_message "Processing incremental backup for: $ks_name.$table_name"
    
    s3_path="s3://$S3_BUCKET_NAME/$HOSTNAME/$BACKUP_TAG/$ks_name/$table_name/incremental.tar.gz.enc"
    
    if [ "$UPLOAD_STREAMING" = "true" ]; then
        # Streaming pipeline
        tar -C "$backup_dir" -c . | \
        gzip | \
        openssl enc -aes-256-cbc -salt -pbkdf2 -pass "file:$TMP_KEY_FILE" | \
        aws s3 cp - "$s3_path"
        
        pipeline_status=("${PIPESTATUS[@]}")
        if [ ${pipeline_status[0]} -ne 0 ] || [ ${pipeline_status[1]} -ne 0 ] || [ ${pipeline_status[2]} -ne 0 ] || [ ${pipeline_status[3]} -ne 0 ]; then
            log_message "ERROR: Streaming backup failed for $ks_name.$table_name. tar: ${pipeline_status[0]}, gzip: ${pipeline_status[1]}, openssl: ${pipeline_status[2]}, aws: ${pipeline_status[3]}"
            log_message "Local incremental files will not be deleted."
            UPLOAD_ERRORS=$((UPLOAD_ERRORS + 1))
        else
            log_message "Successfully streamed incremental backup for $ks_name.$table_name"
            TABLES_BACKED_UP=$(echo "$TABLES_BACKED_UP" | jq ". + [\"$ks_name.$table_name\"]")
            log_message "Cleaning up local incremental files for $ks_name.$table_name"
            rm -f "$backup_dir"/*
        fi
    else
        # Non-streaming (safer) method
        local_tar_file="$BACKUP_TEMP_DIR/$ks_name.$table_name.tar.gz"
        local_enc_file="$BACKUP_TEMP_DIR/$ks_name.$table_name.tar.gz.enc"

        # Step 1: Archive and compress
        if ! tar -C "$backup_dir" -czf "$local_tar_file" .; then
            log_message "ERROR: Failed to archive incremental backup for $ks_name.$table_name. Skipping."
            UPLOAD_ERRORS=$((UPLOAD_ERRORS + 1))
            continue
        fi

        # Step 2: Encrypt
        if ! openssl enc -aes-256-cbc -salt -pbkdf2 -in "$local_tar_file" -out "$local_enc_file" -pass "file:$TMP_KEY_FILE"; then
            log_message "ERROR: Failed to encrypt incremental backup for $ks_name.$table_name. Skipping."
            UPLOAD_ERRORS=$((UPLOAD_ERRORS + 1))
            rm -f "$local_tar_file"
            continue
        fi
        
        # Step 3: Upload
        if aws s3 cp "$local_enc_file" "$s3_path"; then
            log_message "Successfully uploaded incremental backup for $ks_name.$table_name"
            TABLES_BACKED_UP=$(echo "$TABLES_BACKED_UP" | jq ". + [\"$ks_name.$table_name\"]")
            
            log_message "Cleaning up local incremental files for $ks_name.$table_name"
            rm -f "$backup_dir"/*
        else
            log_message "ERROR: Failed to upload incremental backup for $ks_name.$table_name. Local files will not be deleted."
            UPLOAD_ERRORS=$((UPLOAD_ERRORS + 1))
        fi

        # Step 4: Cleanup local temp files
        rm -f "$local_tar_file" "$local_enc_file"
    fi
done

if [ "$UPLOAD_ERRORS" -gt 0 ]; then
    log_message "ERROR: $UPLOAD_ERRORS incremental backup(s) failed to upload. The backup is incomplete."
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
