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

# Check for required tools
for tool in jq aws openssl nodetool cqlsh; do
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
LOG_FILE=$(jq -r '.full_backup_log_file' "$CONFIG_FILE")
LISTEN_ADDRESS=$(jq -r '.listen_address' "$CONFIG_FILE")
KEEP_DAYS=$(jq -r '.clearsnapshot_keep_days // 0' "$CONFIG_FILE")
# upload_streaming is deprecated in this new model

# Validate sourced config
if [ -z "$S3_BUCKET_NAME" ] || [ -z "$CASSANDRA_DATA_DIR" ] || [ -z "$LOG_FILE" ]; then
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: One or more required configuration values are missing from $CONFIG_FILE"
  exit 1
fi

# --- Static Configuration ---
BACKUP_TAG=$(date +'%Y-%m-%d-%H-%M') # NEW timestamp format
HOSTNAME=$(hostname -s)
BACKUP_TEMP_DIR="/tmp/cassandra_backups_$$" # Use PID to ensure uniqueness
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
    log_message "Aborting backup before taking a snapshot to prevent wasted effort."
    return 1
  fi
  log_message "INFO: AWS credentials are valid."
  return 0
}


# --- Cleanup Snapshot Function ---
cleanup_old_snapshots() {
    if ! [[ "$KEEP_DAYS" =~ ^[0-9]+$ ]] || [ "$KEEP_DAYS" -le 0 ]; then
        log_message "INFO: Snapshot retention is not configured to a positive number ($KEEP_DAYS). Skipping old snapshot cleanup."
        return
    fi

    log_message "--- Starting Old Snapshot Cleanup ---"
    log_message "Retention period: $KEEP_DAYS days"
    
    local cutoff_timestamp_days
    cutoff_timestamp_days=$(date -d "-$KEEP_DAYS days" +%s)

    # Filter out headers and footers from nodetool output before processing
    nodetool listsnapshots | grep -Ev '^(Snapshot Details:|Snapshot name:|Total snapshots:|There are no snapshots)$' | while read -r snapshot_line; do
      if [[ -z "$snapshot_line" ]]; then
          continue
      fi

      local tag
      tag=$(echo "$snapshot_line" | awk '{print $1}')
      local snapshot_timestamp=0
      
      # Try to parse YYYY-MM-DD-HH-MM format
      if [[ "$tag" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{2}-[0-9]{2}$ ]]; then
          local parsable_date
          parsable_date="${tag:0:10} ${tag:11:2}:${tag:14:2}"
          snapshot_timestamp=$(date -d "$parsable_date" +%s 2>/dev/null || echo 0)
      # Try to parse legacy formats
      elif [[ "$tag" =~ ^(full_snapshot_|backup_|adhoc_snapshot_)([0-9]{8}|[0-9]{14}) ]]; then
          local snapshot_date_str=${BASH_REMATCH[2]}
          if [ ${#snapshot_date_str} -eq 8 ]; then # YYYYMMDD
              snapshot_timestamp=$(date -d "$snapshot_date_str" +%s 2>/dev/null || echo 0)
          elif [ ${#snapshot_date_str} -eq 14 ]; then # YYYYMMDDHHMMSS
              snapshot_timestamp=$(date -d "${snapshot_date_str:0:8} ${snapshot_date_str:8:2}:${snapshot_date_str:10:2}:${snapshot_date_str:12:2}" +%s 2>/dev/null || echo 0)
          fi
      fi
      
      if [[ "$snapshot_timestamp" -gt 0 ]]; then
        if [ "$snapshot_timestamp" -lt "$cutoff_timestamp_days" ]; then
          log_message "Deleting old snapshot: $tag (timestamp: $snapshot_timestamp is older than cutoff: $cutoff_timestamp_days)"
          if ! nodetool clearsnapshot -t "$tag"; then
            log_message "ERROR: Failed to delete snapshot $tag"
          fi
        fi
      else
        log_message "WARNING: Could not parse date from snapshot tag '$tag'. Skipping."
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


# Run cleanup of old snapshots BEFORE taking a new one
cleanup_old_snapshots

log_message "--- Starting Granular Cassandra Snapshot Backup Process ---"
log_message "S3 Bucket: $S3_BUCKET_NAME"
log_message "Backup Timestamp (Tag): $BACKUP_TAG"

# 1. Create temporary directory for manifest
mkdir -p "$BACKUP_TEMP_DIR" || { log_message "ERROR: Failed to create temp backup directory."; exit 1; }

# 2. Take a node-local snapshot
log_message "Taking full snapshot with tag: $BACKUP_TAG..."
if ! nodetool snapshot -t "$BACKUP_TAG"; then
  log_message "ERROR: Failed to take Cassandra snapshot. Aborting backup."
  exit 1
fi
log_message "Full snapshot taken successfully."

# 3. Archive and Upload, per-table
log_message "Discovering keyspaces and tables to back up..."
SYSTEM_KEYSPACES="system system_auth system_distributed system_schema system_traces system_views system_virtual_schema dse_system dse_perf dse_security solr_admin"
TABLES_BACKED_UP="[]"
UPLOAD_ERRORS=0

# Determine if SSL is needed for cqlsh
CQLSH_CONFIG="/root/.cassandra/cqlshrc"
CQLSH_SSL_OPT=""
if [ -f "$CQLSH_CONFIG" ] && grep -q '\[ssl\]' "$CQLSH_CONFIG"; then
    log_message "INFO: SSL section found in cqlshrc, using --ssl for cqlsh schema dump."
    CQLSH_SSL_OPT="--ssl"
fi

# Make keyspace discovery more robust by using cqlsh.
KEYSPACES_LIST=$(cqlsh ${CQLSH_SSL_OPT} -e "DESCRIBE KEYSPACES;" 2>/dev/null | xargs)

if [ -z "$KEYSPACES_LIST" ]; then
    log_message "WARNING: Could not discover keyspaces using 'cqlsh -e \"DESCRIBE KEYSPACES;\"'. Skipping table data backup."
else
    # Use a for loop to iterate over the space-separated list from cqlsh
    for ks in $KEYSPACES_LIST; do
        if [[ " $SYSTEM_KEYSPACES " =~ " $ks " ]]; then
            continue
        fi
        log_message "Processing keyspace: $ks"
        
        # Find table directories. They have a UUID suffix.
        find "$CASSANDRA_DATA_DIR/$ks" -mindepth 1 -maxdepth 1 -type d -name "*-*" | while read -r table_dir; do
            table_name=$(basename "$table_dir" | cut -d'-' -f1)
            snapshot_dir="$table_dir/snapshots/$BACKUP_TAG"
            
            # Check if snapshot dir exists and is not empty
            if [ -d "$snapshot_dir" ] && [ -n "$(ls -A "$snapshot_dir")" ]; then
                log_message "Backing up table: $ks.$table_name"
                s3_path="s3://$S3_BUCKET_NAME/$HOSTNAME/$BACKUP_TAG/$ks/$table_name/$table_name.tar.gz.enc"
                
                local_tar_file="$BACKUP_TEMP_DIR/$ks.$table_name.tar.gz"
                local_enc_file="$BACKUP_TEMP_DIR/$ks.$table_name.tar.gz.enc"

                # Step 1: Archive and compress
                if ! tar -C "$snapshot_dir" -czf "$local_tar_file" .; then
                    log_message "ERROR: Failed to archive $ks.$table_name. Skipping."
                    UPLOAD_ERRORS=$((UPLOAD_ERRORS + 1))
                    continue
                fi

                # Step 2: Encrypt
                if ! openssl enc -aes-256-cbc -salt -in "$local_tar_file" -out "$local_enc_file" -pass "file:$TMP_KEY_FILE"; then
                    log_message "ERROR: Failed to encrypt $ks.$table_name. Skipping."
                    UPLOAD_ERRORS=$((UPLOAD_ERRORS + 1))
                    rm -f "$local_tar_file"
                    continue
                fi
                
                # Step 3: Upload
                if ! aws s3 cp "$local_enc_file" "$s3_path"; then
                    log_message "ERROR: Failed to upload backup for $ks.$table_name"
                    UPLOAD_ERRORS=$((UPLOAD_ERRORS + 1))
                else
                    log_message "Successfully uploaded backup for $ks.$table_name"
                    TABLES_BACKED_UP=$(echo "$TABLES_BACKED_UP" | jq ". + [\"$ks.$table_name\"]")
                fi

                # Step 4: Cleanup local temp files
                rm -f "$local_tar_file" "$local_enc_file"
            fi
        done
    done
fi


if [ "$UPLOAD_ERRORS" -gt 0 ]; then
    log_message "ERROR: $UPLOAD_ERRORS table(s) failed to upload. The backup is incomplete."
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

# Tolerate failures in nodetool status for manifest generation
NODE_STATUS_LINE=$(nodetool status | grep "\b$NODE_IP\b" || echo "Unknown UNKNOWN $LISTEN_ADDRESS UNKNOWN UNKNOWN UNKNOWN")
NODE_DC=$(echo "$NODE_STATUS_LINE" | awk '{print $5}')
NODE_RACK=$(echo "$NODE_STATUS_LINE" | awk '{print $6}')
NODE_TOKENS=$(nodetool ring | grep "\b$NODE_IP\b" | awk '{print $NF}' | tr '\n' ',' | sed 's/,$//')

jq -n \
  --arg cluster_name "$CLUSTER_NAME" \
  --arg backup_id "$BACKUP_TAG" \
  --arg backup_type "full" \
  --arg timestamp "$(date --iso-8601=seconds)" \
  --arg node_ip "$NODE_IP" \
  --arg node_dc "$NODE_DC" \
  --arg node_rack "$NODE_RACK" \
  --arg tokens "$NODE_TOKENS" \
  --argjson tables "$TABLES_BACKED_UP" \
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
    },
    "tables_backed_up": $tables
  }' > "$MANIFEST_FILE"

log_message "Manifest created successfully."

# 5. Archive the schema
log_message "Backing up schema..."
SCHEMA_FILE="$BACKUP_TEMP_DIR/schema.cql"
if timeout 30 cqlsh ${CQLSH_SSL_OPT} -e "DESCRIBE SCHEMA;" > "$SCHEMA_FILE"; then
  log_message "Schema backup created successfully."
else
  log_message "WARNING: Failed to dump schema. Backup manifest will be uploaded without it."
  rm -f "$SCHEMA_FILE" # Ensure partial schema file is not uploaded
fi

# 6. Upload Manifest and Schema to S3
if [ -f "/var/lib/upload-disabled" ]; then
    log_message "INFO: S3 upload is disabled via /var/lib/upload-disabled."
    log_message "Backup artifacts are available locally with tag: $BACKUP_TAG"
    log_message "Local snapshot will NOT be automatically cleared."
else
    if [ "$BACKUP_BACKEND" == "s3" ]; then
        log_message "Uploading manifest file..."
        MANIFEST_S3_PATH="s3://$S3_BUCKET_NAME/$HOSTNAME/$BACKUP_TAG/backup_manifest.json"
        if ! aws s3 cp "$MANIFEST_FILE" "$MANIFEST_S3_PATH"; then
          log_message "ERROR: Failed to upload manifest to S3. The backup is not properly indexed."
          exit 1
        fi
        log_message "Manifest uploaded successfully."
        
        if [ -f "$SCHEMA_FILE" ]; then
            log_message "Uploading schema file..."
            SCHEMA_S3_PATH="s3://$S3_BUCKET_NAME/$HOSTNAME/$BACKUP_TAG/schema.cql"
            if ! aws s3 cp "$SCHEMA_FILE" "$SCHEMA_S3_PATH"; then
              log_message "ERROR: Failed to upload schema to S3."
            else
              log_message "Schema uploaded successfully."
            fi
        fi
    else
        log_message "INFO: Backup backend is set to '$BACKUP_BACKEND', not 's3'. Skipping manifest upload."
        log_message "Local snapshot is available with tag: $BACKUP_TAG"
    fi
fi

if [ "$UPLOAD_ERRORS" -gt 0 ]; then
    log_message "--- Granular Cassandra Backup Process Finished with ERRORS ---"
    exit 1
else
    log_message "--- Granular Cassandra Backup Process Finished Successfully ---"
fi

exit 0
