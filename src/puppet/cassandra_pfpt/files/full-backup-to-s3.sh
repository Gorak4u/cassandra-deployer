#!/bin/bash
# Performs a full snapshot backup and uploads it to a simulated S3 bucket.

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
  # Cannot use log_message here as LOG_FILE is not yet defined
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
LOG_FILE=$(jq -r '.full_backup_log_file' "$CONFIG_FILE")
LISTEN_ADDRESS=$(jq -r '.listen_address' "$CONFIG_FILE")
KEEP_DAYS=$(jq -r '.clearsnapshot_keep_days // 0' "$CONFIG_FILE")
UPLOAD_STREAMING=$(jq -r '.upload_streaming // "false"' "$CONFIG_FILE")


# Validate sourced config
if [ -z "$S3_BUCKET_NAME" ] || [ -z "$CASSANDRA_DATA_DIR" ] || [ -z "$LOG_FILE" ]; then
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: One or more required configuration values are missing from $CONFIG_FILE"
  exit 1
fi

# --- Static Configuration ---
SNAPSHOT_TAG="full_snapshot_$(date +%Y%m%d%H%M%S)"
HOSTNAME=$(hostname -s)
BACKUP_ROOT_DIR="/tmp/cassandra_backups"
BACKUP_TEMP_DIR="$BACKUP_ROOT_DIR/${HOSTNAME}_$SNAPSHOT_TAG"

# --- Cleanup Snapshot Function ---
cleanup_old_snapshots() {
    if ! [[ "$KEEP_DAYS" =~ ^[0-9]+$ ]] || [ "$KEEP_DAYS" -le 0 ]; then
        log_message "INFO: Snapshot retention is not configured to a positive number ($KEEP_DAYS). Skipping old snapshot cleanup."
        return
    fi

    log_message "--- Starting Old Snapshot Cleanup ---"
    log_message "Retention period: $KEEP_DAYS days"
    local cutoff_date
    cutoff_date=$(date -d "-$KEEP_DAYS days" +%Y%m%d)

    nodetool listsnapshots | while read -r snapshot_line; do
      if [[ "$snapshot_line" =~ ^(full_snapshot_|adhoc_snapshot_|snapshot_) ]]; then
        local tag
        tag=$(echo "$snapshot_line" | awk '{print $1}')
        # Extract date from tag like 'full_snapshot_YYYYMMDDHHMMSS'
        local snapshot_date
        snapshot_date=$(echo "$tag" | sed -n 's/^.*_\([0-9]\{8\}\)[0-9]\{6\}$/\1/p')

        if [ -n "$snapshot_date" ]; then
          if [ "$snapshot_date" -lt "$cutoff_date" ]; then
            log_message "Deleting old snapshot: $tag (date: $snapshot_date is older than cutoff: $cutoff_date)"
            if ! nodetool clearsnapshot -t "$tag"; then
              log_message "ERROR: Failed to delete snapshot $tag"
            fi
          fi
        fi
      fi
    done
    log_message "--- Snapshot Cleanup Finished ---"
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

trap cleanup_temp_dir EXIT

# Check for global backup disable flag
if [ -f "/var/lib/backup-disabled" ]; then
    log_message "INFO: Backup is disabled via /var/lib/backup-disabled. Aborting."
    exit 0
fi

# Run cleanup of old snapshots BEFORE taking a new one
cleanup_old_snapshots

log_message "--- Starting Full Cassandra Snapshot Backup Process ---"
log_message "S3 Bucket: $S3_BUCKET_NAME"
log_message "Snapshot Tag: $SNAPSHOT_TAG"
log_message "Upload Streaming: $UPLOAD_STREAMING"

# 1. Create temporary directory structure
mkdir -p "$BACKUP_TEMP_DIR" || { log_message "ERROR: Failed to create temp backup directories."; exit 1; }

# 2. Create Backup Manifest
MANIFEST_FILE="$BACKUP_TEMP_DIR/backup_manifest.json"
log_message "Creating backup manifest at $MANIFEST_FILE..."

CLUSTER_NAME=$(nodetool describecluster | grep 'Name:' | awk '{print $2}')

if [ -n "$LISTEN_ADDRESS" ]; then
    NODE_IP="$LISTEN_ADDRESS"
else
    NODE_IP="$(hostname -i)"
fi

NODE_STATUS_LINE=$(nodetool status | grep "\b$NODE_IP\b")
NODE_DC=$(echo "$NODE_STATUS_LINE" | awk '{print $5}')
NODE_RACK=$(echo "$NODE_STATUS_LINE" | awk '{print $6}')
NODE_TOKENS=$(nodetool ring | grep "\b$NODE_IP\b" | awk '{print $NF}' | tr '\n' ',' | sed 's/,$//')

jq -n \
  --arg cluster_name "$CLUSTER_NAME" \
  --arg backup_id "$SNAPSHOT_TAG" \
  --arg backup_type "full" \
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


# 3. Take a node-local snapshot
log_message "Taking full snapshot with tag: $SNAPSHOT_TAG..."
if ! nodetool snapshot -t "$SNAPSHOT_TAG"; then
  log_message "ERROR: Failed to take Cassandra snapshot. Aborting backup."
  exit 1
fi
log_message "Full snapshot taken successfully."

# 4. Collect snapshot file paths
find "$CASSANDRA_DATA_DIR" -type f -path "*/snapshots/$SNAPSHOT_TAG/*" > "$BACKUP_TEMP_DIR/snapshot_files.list"

# 5. Archive the files
TARBALL_PATH="$BACKUP_ROOT_DIR/${HOSTNAME}_${SNAPSHOT_TAG}.tar.gz"
UNCOMPRESSED_TAR_PATH="$BACKUP_ROOT_DIR/${HOSTNAME}_${SNAPSHOT_TAG}.tar"

# Check if there are snapshot files before proceeding
if [ ! -s "$BACKUP_TEMP_DIR/snapshot_files.list" ]; then
    log_message "WARNING: No snapshot files found. The cluster may be empty. Aborting backup."
    nodetool clearsnapshot -t "$SNAPSHOT_TAG"
    exit 0
fi

# 6. Archive the schema
log_message "Backing up schema..."
SCHEMA_FILE="$BACKUP_TEMP_DIR/schema.cql"
# Determine if SSL is needed for cqlsh
CQLSH_CONFIG="/root/.cassandra/cqlshrc"
CQLSH_SSL_OPT=""
if [ -f "$CQLSH_CONFIG" ] && grep -q '\[ssl\]' "$CQLSH_CONFIG"; then
    log_message "INFO: SSL section found in cqlshrc, using --ssl for cqlsh schema dump."
    CQLSH_SSL_OPT="--ssl"
fi
# Use a timeout to prevent cqlsh from hanging indefinitely
timeout 30 cqlsh ${CQLSH_SSL_OPT} -e "DESCRIBE SCHEMA;" > "$SCHEMA_FILE"
if [ $? -ne 0 ]; then
  log_message "WARNING: Failed to dump schema. Backup will continue without it."
else
  log_message "Schema backup created successfully."
fi

# 7. Create local archive or prepare for streaming
if [ "$UPLOAD_STREAMING" == "true" ]; then
    log_message "Streaming mode enabled. Local tarball creation will be skipped."
else
    log_message "Creating uncompressed archive of snapshot files..."
    tar -cf "$UNCOMPRESSED_TAR_PATH" -C / --files-from=<(sed 's#^/##' "$BACKUP_TEMP_DIR/snapshot_files.list")

    log_message "Appending manifest to archive..."
    tar -rf "$UNCOMPRESSED_TAR_PATH" -C "$BACKUP_TEMP_DIR" "backup_manifest.json"

    if [ -f "$SCHEMA_FILE" ]; then
      log_message "Appending schema to archive..."
      tar -rf "$UNCOMPRESSED_TAR_PATH" -C "$BACKUP_TEMP_DIR" "schema.cql"
    fi
    
    log_message "Compressing the final archive..."
    gzip -c "$UNCOMPRESSED_TAR_PATH" > "$TARBALL_PATH"
    rm -f "$UNCOMPRESSED_TAR_PATH"
    log_message "Archive compressed and temporary tar file removed."
fi


# 8. Upload to S3 and Cleanup
if [ -f "/var/lib/upload-disabled" ]; then
    log_message "INFO: S3 upload is disabled via /var/lib/upload-disabled."
    if [ "$UPLOAD_STREAMING" == "false" ]; then
        log_message "Backup archive is available at: $TARBALL_PATH"
    fi
    log_message "Snapshot is available with tag: $SNAPSHOT_TAG"
    log_message "Skipping S3 upload and local cleanup."
else
    if [ "$BACKUP_BACKEND" == "s3" ]; then
        BACKUP_DATE=$(date +%Y-%m-%d)
        UPLOAD_PATH="s3://$S3_BUCKET_NAME/cassandra/$HOSTNAME/$BACKUP_DATE/full/$SNAPSHOT_TAG.tar.gz"

        if [ "$UPLOAD_STREAMING" == "true" ]; then
            log_message "Streaming backup directly to S3: $UPLOAD_PATH"
            
            # This pipeline creates a concatenated tar stream from multiple sources,
            # gzips it, and pipes it directly to the aws-cli.
            {
                tar -cf - -C / --files-from=<(sed 's#^/##' "$BACKUP_TEMP_DIR/snapshot_files.list");
                tar -cf - -C "$BACKUP_TEMP_DIR" "backup_manifest.json";
                if [ -f "$SCHEMA_FILE" ]; then
                    tar -cf - -C "$BACKUP_TEMP_DIR" "schema.cql";
                fi
            } | gzip -c | aws s3 cp - "$UPLOAD_PATH"

            if [ ${PIPESTATUS[2]} -ne 0 ]; then
                log_message "ERROR: Backup stream failed. Check logs for details from tar, gzip, or aws-cli."
                exit 1
            fi
            
            log_message "S3 stream upload completed successfully."
            # No local tarball to remove in streaming mode.

        else # The original non-streaming logic
            log_message "Uploading local archive to S3: $UPLOAD_PATH"
            if ! aws s3 cp "$TARBALL_PATH" "$UPLOAD_PATH"; then
              log_message "ERROR: Failed to upload backup to S3. Local files will not be cleaned up."
              exit 1
            fi
            log_message "S3 upload completed successfully."

            # Cleanup (only after successful upload)
            log_message "Cleaning up local archive file..."
            rm -f "$TARBALL_PATH"
        fi
    else
        log_message "INFO: Backup backend is set to '$BACKUP_BACKEND', not 's3'. Skipping upload."
        if [ "$UPLOAD_STREAMING" == "false" ]; then
            log_message "Backup archive is available at: $TARBALL_PATH"
        fi
        log_message "Snapshot is available with tag: $SNAPSHOT_TAG"
        log_message "Local files will NOT be cleaned up."
    fi
fi

log_message "--- Full Cassandra Snapshot Backup Process Finished Successfully ---"

exit 0
