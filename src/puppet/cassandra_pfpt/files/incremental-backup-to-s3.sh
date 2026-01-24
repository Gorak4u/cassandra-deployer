#!/bin/bash
# Archives and uploads existing incremental backup files to a simulated S3 bucket.

set -euo pipefail

# This script needs to run with /bin/bash to support PIPESTATUS
if [ -z "$BASH_VERSION" ]; then
    exec /bin/bash "$0" "$@"
fi

# --- Color Codes ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# --- Configuration & Logging Initialization ---
CONFIG_FILE="/etc/backup/config.json"
# Define a default log file path in case config loading fails, ensuring early errors are logged.
LOG_FILE="/var/log/cassandra/incremental_backup.log"

log_message() {
  # This version of log_message does not add colors, as the caller functions will.
  echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log_info() {
    log_message "${BLUE}$1${NC}"
}
log_success() {
    log_message "${GREEN}$1${NC}"
}
log_warn() {
    log_message "${YELLOW}$1${NC}"
}
log_error() {
    log_message "${RED}$1${NC}"
}

# --- Pre-flight Checks ---
# Check for required tools first, so we can log errors if they are missing.
for tool in jq aws openssl nodetool; do
    if ! command -v $tool &> /dev/null; then
        log_error "Required tool '$tool' is not installed or in PATH."
        exit 1
    fi
done

# Check for config file
if [ ! -f "$CONFIG_FILE" ]; then
  log_error "Backup configuration file not found at $CONFIG_FILE"
  exit 1
fi

# --- Source All Configuration from JSON ---
S3_BUCKET_NAME=$(jq -r '.s3_bucket_name' "$CONFIG_FILE")
BACKUP_BACKEND=$(jq -r '.backup_backend // "s3"' "$CONFIG_FILE")
CASSANDRA_DATA_DIR=$(jq -r '.cassandra_data_dir' "$CONFIG_FILE")
# Overwrite the default LOG_FILE with the one from the config.
LOG_FILE=$(jq -r '.incremental_backup_log_file' "$CONFIG_FILE")
LISTEN_ADDRESS=$(jq -r '.listen_address' "$CONFIG_FILE")
UPLOAD_STREAMING=$(jq -r '.upload_streaming // "false"' "$CONFIG_FILE")


# Validate sourced config
if [ -z "$S3_BUCKET_NAME" ] || [ -z "$CASSANDRA_DATA_DIR" ] || [ -z "$LOG_FILE" ]; then
  log_error "One or more required configuration values are missing from $CONFIG_FILE"
  exit 1
fi

# --- Static Configuration ---
BACKUP_TAG=$(date +'%Y-%m-%d-%H-%M')
HOSTNAME=$(hostname -s)
BACKUP_TEMP_DIR="${CASSANDRA_DATA_DIR%/*}/backup_temp_$$"
LOCK_FILE="/var/run/cassandra_backup.lock"
ERROR_DIR="$BACKUP_TEMP_DIR/errors"


# --- AWS Credential Check Function ---
check_aws_credentials() {
  # Skip check if backend isn't S3 or if uploads are disabled via flag file
  if [ "$BACKUP_BACKEND" != "s3" ] || [ -f "/var/lib/upload-disabled" ]; then
    return 0
  fi
  
  log_info "Verifying AWS credentials..."
  if ! aws sts get-caller-identity > /dev/null 2>&1; then
    log_error "AWS credentials not found or invalid."
    log_error "Please configure credentials for this node, e.g., via an IAM role."
    log_error "Aborting backup."
    return 1
  fi
  log_success "AWS credentials are valid."
  return 0
}

# --- S3 Bucket Management Functions ---
ensure_s3_bucket_exists() {
    if [ "$BACKUP_BACKEND" != "s3" ]; then
        return 0
    fi
    log_info "Checking if S3 bucket 's3://$S3_BUCKET_NAME' exists..."
    if aws s3api head-bucket --bucket "$S3_BUCKET_NAME" > /dev/null 2>&1; then
        log_success "S3 bucket already exists."
        return 0
    else
        log_warn "S3 bucket '$S3_BUCKET_NAME' does not exist. Attempting to create it..."
        if aws s3 mb "s3://$S3_BUCKET_NAME"; then
            log_success "Successfully created S3 bucket '$S3_BUCKET_NAME'."
            return 0
        else
            log_error "Failed to create S3 bucket '$S3_BUCKET_NAME'."
            log_error "Please check your AWS permissions (s3:CreateBucket) and ensure the bucket name is globally unique."
            return 1
        fi
    fi
}

# --- Cleanup Functions ---
cleanup_temp_dir() {
  if [ -d "$BACKUP_TEMP_DIR" ]; then
    log_info "Cleaning up temporary directory: $BACKUP_TEMP_DIR"
    rm -rf "$BACKUP_TEMP_DIR"
  fi
}

# --- Main Logic ---
if [ "$(id -u)" -ne 0 ]; then
  log_error "This script must be run as root."
  exit 1
fi

# Pre-flight checks before creating a lock or doing any work
if [ -f "/var/lib/backup-disabled" ]; then
    log_info "Backup is disabled via /var/lib/backup-disabled. Aborting."
    exit 0
fi

# Check for incremental files first, so we don't run all the checks if there's nothing to do.
INCREMENTAL_DIRS_COUNT=$(find "$CASSANDRA_DATA_DIR" -type d -name "backups" -not -empty -print | wc -l)
if [ "$INCREMENTAL_DIRS_COUNT" -eq 0 ]; then
    log_info "No new incremental backup files found. Nothing to do."
    exit 0
fi

if ! check_aws_credentials; then
    exit 1
fi

if ! ensure_s3_bucket_exists; then
    exit 1
fi

if [ -f "$LOCK_FILE" ]; then
    log_warn "Lock file $LOCK_FILE exists. Checking if process is running..."
    OLD_PID=$(cat "$LOCK_FILE")
    if ps -p "$OLD_PID" > /dev/null; then
        log_warn "Backup process with PID $OLD_PID is still running. Exiting."
        exit 1
    else
        log_warn "Stale lock file found for dead PID $OLD_PID. Removing."
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
    log_error "encryption_key is empty or not found in $CONFIG_FILE"
    exit 1
fi
echo -n "$ENCRYPTION_KEY" > "$TMP_KEY_FILE"


log_info "--- Starting Granular Incremental Cassandra Backup Process ---"
log_info "S3 Bucket: $S3_BUCKET_NAME"
log_info "Backup Timestamp (Tag): $BACKUP_TAG"
log_info "Streaming Mode: $UPLOAD_STREAMING"


# Create manifest and temp dir
mkdir -p "$BACKUP_TEMP_DIR"
mkdir -p "$ERROR_DIR"
MANIFEST_FILE="$BACKUP_TEMP_DIR/backup_manifest.json"

TABLES_BACKED_UP="[]"
# Define system keyspaces to exclude, allowing system_auth to be backed up
INCLUDED_SYSTEM_KEYSPACES="system_schema system_auth system_distributed"

# Create a mapping of clean table names to their UUID-based directory names
SCHEMA_MAP_FILE="$BACKUP_TEMP_DIR/schema_mapping.json"
SCHEMA_MAP="{}"
while IFS= read -r table_path; do
    ks_name_map=$(basename "$(dirname "$table_path")")
    table_dir_name_map=$(basename "$table_path")
    table_name_map=$(echo "$table_dir_name_map" | rev | cut -d'-' -f2- | rev)
    
    is_system_ks_to_skip=true
    for included_ks_map in $INCLUDED_SYSTEM_KEYSPACES; do
        if [ "$ks_name_map" == "$included_ks_map" ]; then is_system_ks_to_skip=false; break; fi
    done
    if [[ "$ks_name_map" == system* || "$ks_name_map" == dse* || "$ks_name_map" == solr* ]] && [ "$is_system_ks_to_skip" = true ]; then continue; fi

    SCHEMA_MAP=$(echo "$SCHEMA_MAP" | jq --arg key "${ks_name_map}.${table_name_map}" --arg val "$table_dir_name_map" '. + {($key): $val}')
done < <(find "$CASSANDRA_DATA_DIR" -maxdepth 2 -mindepth 2 -type d -not -path '*/snapshots' -not -path '*/backups')

echo "$SCHEMA_MAP" > "$SCHEMA_MAP_FILE"
log_info "Schema-to-directory mapping generated."

# Use a robust find and while loop to handle any filenames
find "$CASSANDRA_DATA_DIR" -type d -name "backups" -not -empty -print0 | while IFS= read -r -d $'\0' backup_dir; do
    relative_path=${backup_dir#$CASSANDRA_DATA_DIR/}
    ks_name=$(echo "$relative_path" | cut -d'/' -f1)

    is_system_ks=false
    for included_ks in $INCLUDED_SYSTEM_KEYSPACES; do
        if [ "$ks_name" == "$included_ks" ]; then
            is_system_ks=true
            break
        fi
    done

    if [[ "$ks_name" == system* || "$ks_name" == dse* || "$ks_name" == solr* ]] && [ "$is_system_ks" = false ]; then
        continue
    fi
    
    table_dir_name=$(echo "$relative_path" | cut -d'/' -f2)
    table_name=$(echo "$table_dir_name" | rev | cut -d'-' -f2- | rev)
    
    log_info "Processing incremental backup for: $ks_name.$table_name"
    
    if [ "$BACKUP_BACKEND" == "s3" ]; then
        s3_path="s3://$S3_BUCKET_NAME/$HOSTNAME/$BACKUP_TAG/$ks_name/$table_name/incremental.tar.gz.enc"
        
        if [ "$UPLOAD_STREAMING" = "true" ]; then
            # Streaming pipeline
            nice -n 19 ionice -c 3 tar -C "$backup_dir" -c . | \
            gzip | \
            openssl enc -aes-256-cbc -salt -pbkdf2 -md sha256 -pass "file:$TMP_KEY_FILE" | \
            nice -n 19 ionice -c 3 aws s3 cp - "$s3_path"
            
            pipeline_status=("${PIPESTATUS[@]}")
            if [ ${pipeline_status[0]} -ne 0 ] || [ ${pipeline_status[1]} -ne 0 ] || [ ${pipeline_status[2]} -ne 0 ] || [ ${pipeline_status[3]} -ne 0 ]; then
                log_error "Streaming backup failed for $ks_name.$table_name. tar: ${pipeline_status[0]}, gzip: ${pipeline_status[1]}, openssl: ${pipeline_status[2]}, aws: ${pipeline_status[3]}"
                log_warn "Local incremental files will not be deleted."
                touch "$ERROR_DIR/$ks_name.$table_name"
            else
                log_success "Successfully streamed incremental backup for $ks_name.$table_name"
                TABLES_BACKED_UP=$(echo "$TABLES_BACKED_UP" | jq ". + [\"$ks_name/$table_name\"]")
                
                log_info "Cleaning up local incremental files for $ks_name.$table_name"
                rm -f "$backup_dir"/*
            fi
        else
            # Non-streaming (safer) method
            local_tar_file="$BACKUP_TEMP_DIR/$ks_name.$table_name.tar.gz"
            local_enc_file="$BACKUP_TEMP_DIR/$ks_name.$table_name.tar.gz.enc"

            # Step 1: Archive and compress
            if ! nice -n 19 ionice -c 3 tar -C "$backup_dir" -czf "$local_tar_file" .; then
                log_error "Failed to archive incremental backup for $ks_name.$table_name. Skipping."
                touch "$ERROR_DIR/$ks_name.$table_name"
                continue
            fi

            # Step 2: Encrypt
            if ! nice -n 19 ionice -c 3 openssl enc -aes-256-cbc -salt -pbkdf2 -md sha256 -in "$local_tar_file" -out "$local_enc_file" -pass "file:$TMP_KEY_FILE"; then
                log_error "Failed to encrypt incremental backup for $ks_name.$table_name. Skipping."
                touch "$ERROR_DIR/$ks_name.$table_name"
                rm -f "$local_tar_file"
                continue
            fi
            
            # Step 3: Upload
            if nice -n 19 ionice -c 3 aws s3 cp "$local_enc_file" "$s3_path"; then
                log_success "Successfully uploaded incremental backup for $ks_name.$table_name"
                TABLES_BACKED_UP=$(echo "$TABLES_BACKED_UP" | jq ". + [\"$ks_name/$table_name\"]")
                
                log_info "Cleaning up local incremental files for $ks_name.$table_name"
                rm -f "$backup_dir"/*
            else
                log_error "Failed to upload incremental backup for $ks_name.$table_name. Local files will not be deleted."
                touch "$ERROR_DIR/$ks_name.$table_name"
            fi

            # Step 4: Cleanup local temp files
            rm -f "$local_tar_file" "$local_enc_file"
        fi
    else
        log_info "Backup backend is '$BACKUP_BACKEND', not 's3'. Skipping upload for $ks_name.$table_name."
        log_warn "IMPORTANT: Local incremental files at '$backup_dir' are NOT deleted for non-S3 backends."
        TABLES_BACKED_UP=$(echo "$TABLES_BACKED_UP" | jq ". + [\"$ks_name/$table_name\"]")
    fi
done

# Create and Upload Manifest
log_info "Creating backup manifest at $MANIFEST_FILE..."

TOTAL_TABLES_WITH_INCREMENTALS=$(find "$CASSANDRA_DATA_DIR" -type d -name "backups" -not -empty | wc -l)
UPLOAD_ERRORS=$(find "$ERROR_DIR" -type f 2>/dev/null | wc -l)
TABLES_BACKED_UP_COUNT=$(echo "$TABLES_BACKED_UP" | jq 'length')

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
    log_info "S3 upload is disabled. Manifest and backups are local."
else
    if [ "$BACKUP_BACKEND" == "s3" ]; then
        log_info "Uploading manifest file..."
        MANIFEST_S3_PATH="s3://$S3_BUCKET_NAME/$HOSTNAME/$BACKUP_TAG/backup_manifest.json"
        if ! aws s3 cp "$MANIFEST_FILE" "$MANIFEST_S3_PATH"; then
            log_error "Failed to upload manifest to S3. The backup is not properly indexed."
        else
            log_success "Manifest uploaded successfully."
        fi

        log_info "Uploading schema mapping file..."
        SCHEMA_MAP_S3_PATH="s3://$S3_BUCKET_NAME/$HOSTNAME/$BACKUP_TAG/schema_mapping.json"
        if ! aws s3 cp "$SCHEMA_MAP_FILE" "$SCHEMA_MAP_S3_PATH"; then
            log_error "Failed to upload schema mapping file to S3."
        else
            log_success "Schema mapping file uploaded successfully."
        fi
    fi
fi

if [ "$UPLOAD_ERRORS" -gt 0 ]; then
    log_error "--- Granular Incremental Backup Process Finished with $UPLOAD_ERRORS ERRORS ---"
    log_error "Summary: $TABLES_BACKED_UP_COUNT / $TOTAL_TABLES_WITH_INCREMENTALS tables with new data backed up successfully."
    log_error "The following tables failed to back up:"
    for f in "$ERROR_DIR"/*; do
        log_error "  - $(basename "$f")"
    done
    exit 1
else
    log_success "--- Granular Incremental Backup Process Finished Successfully ---"
    if [ "$TABLES_BACKED_UP_COUNT" -gt 0 ]; then
        log_success "Summary: All $TABLES_BACKED_UP_COUNT tables with new data backed up successfully."
    fi
fi

exit 0
