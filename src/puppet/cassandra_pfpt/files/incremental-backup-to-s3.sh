#!/bin/bash
# Archives and uploads existing incremental backup files to a simulated S3 bucket.

set -euo pipefail

# --- Configuration from JSON file ---
CONFIG_FILE="/etc/backup/config.json"

# --- Logging ---
# This function will be defined after LOG_FILE is sourced from config
log_message() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Check for config file and jq
if ! command -v jq &> /dev/null; then
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: jq is not installed. Please install jq to continue."
  exit 1
fi

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
BACKUP_TAG="incremental_$(date +%Y%m%d%H%M%S)"
HOSTNAME=$(hostname -s)
BACKUP_ROOT_DIR="/tmp/cassandra_backups"
BACKUP_TEMP_DIR="$BACKUP_ROOT_DIR/${HOSTNAME}_$BACKUP_TAG"

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

log_message "--- Starting Incremental Cassandra Backup Process ---"
log_message "S3 Bucket: $S3_BUCKET_NAME"
log_message "Backup Tag: $BACKUP_TAG"

# 1. Create temporary directory structure
mkdir -p "$BACKUP_TEMP_DIR" || { log_message "ERROR: Failed to create temp backup directory."; exit 1; }


# 2. Collect incremental backup file paths
find "$CASSANDRA_DATA_DIR" -type f -path "*/backups/*" > "$BACKUP_TEMP_DIR/incremental_files.list"

# 3. Check if there are files to back up
if [ ! -s "$BACKUP_TEMP_DIR/incremental_files.list" ]; then
    log_message "No new incremental backup files found. Nothing to do."
    exit 0
fi

# 4. Create Backup Manifest
MANIFEST_FILE="$BACKUP_TEMP_DIR/backup_manifest.json"
log_message "Creating backup manifest at $MANIFEST_FILE..."

CLUSTER_NAME=$(nodetool describecluster | grep 'Name:' | awk '{print $2}')

if [ -n "$LISTEN_ADDRESS" ]; then
    NODE_IP="$LISTEN_ADDRESS"
else
    NODE_IP="$(hostname -i)"
fi

NODE_STATUS_LINE=$(nodetool status | grep "\\b$NODE_IP\\b")
NODE_DC=$(echo "$NODE_STATUS_LINE" | awk '{print $5}')
NODE_RACK=$(echo "$NODE_STATUS_LINE" | awk '{print $6}')
NODE_TOKENS=$(nodetool ring | grep "\\b$NODE_IP\\b" | awk '{print $NF}' | tr '\n' ',' | sed 's/,$//')

jq -n \
  --arg cluster_name "$CLUSTER_NAME" \
  --arg backup_id "$BACKUP_TAG" \
  --arg backup_type "incremental" \
  --arg timestamp "$(date --iso-8601=seconds)" \
  --arg node_ip "$NODE_IP" \
  --arg node_dc "$NODE_DC" \
  --arg node_rack "$NODE_RACK" \
  --arg tokens "$NODE_TOKENS" \
  '{
    "cluster_name": $cluster_name,
    "backup_id": $backup_id,
    "backup_type": $backup_type,
    "timestamp_utc": $timestamp,
    "source_node": {
      "ip_address": $node_ip,
      "datacenter": $node_dc,
      "rack": $node_rack,
      "tokens": ($tokens | split(","))
    }
  }' > "$MANIFEST_FILE"

log_message "Manifest created successfully."


# 5. Archive the files
TARBALL_PATH_UNCOMPRESSED="$BACKUP_ROOT_DIR/${HOSTNAME}_$BACKUP_TAG.tar"
TARBALL_PATH="$TARBALL_PATH_UNCOMPRESSED.gz"
log_message "Archiving incremental data to $TARBALL_PATH..."

tar -cf "$TARBALL_PATH_UNCOMPRESSED" --absolute-names -T "$BACKUP_TEMP_DIR/incremental_files.list"
tar -rf "$TARBALL_PATH_UNCOMPRESSED" -C "$BACKUP_TEMP_DIR" "backup_manifest.json"
log_message "Backup manifest appended to archive."

# 6. Compress the archive
log_message "Compressing the archive..."
gzip "$TARBALL_PATH_UNCOMPRESSED"
log_message "Archive compressed successfully."


# 7. Upload to S3 and Cleanup
if [ -f "/var/lib/upload-disabled" ]; then
    log_message "INFO: S3 upload is disabled via /var/lib/upload-disabled."
    log_message "Backup archive is available at: $TARBALL_PATH"
    log_message "Incremental backup files have NOT been cleaned up and will be included in the next run."
else
    if [ "$BACKUP_BACKEND" == "s3" ]; then
        BACKUP_DATE=$(date +%Y-%m-%d)
        UPLOAD_PATH="s3://$S3_BUCKET_NAME/cassandra/$HOSTNAME/$BACKUP_DATE/incremental/$BACKUP_TAG.tar.gz"
        log_message "Simulating S3 upload to: $UPLOAD_PATH"
        # In a real environment: aws s3 cp "$TARBALL_PATH" "$UPLOAD_PATH"
        log_message "S3 upload simulated successfully."

        # 8. Cleanup (only after successful upload)
        log_message "Cleaning up archived incremental backup files and local tarball..."
        xargs -a "$BACKUP_TEMP_DIR/incremental_files.list" rm -f
        log_message "Source incremental files deleted."
        rm -f "$TARBALL_PATH"
        log_message "Local tarball deleted."
    else
        log_message "INFO: Backup backend is set to '$BACKUP_BACKEND', not 's3'. Skipping upload."
        log_message "Backup archive is available at: $TARBALL_PATH"
        log_message "Incremental backup files have NOT been cleaned up and will be included in the next run."
    fi
fi

log_message "--- Incremental Cassandra Backup Process Finished Successfully ---"

exit 0
