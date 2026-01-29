#!/bin/bash
# This file is managed by Puppet.
# Performs a full snapshot backup and uploads it to S3.

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
LOG_FILE="/var/log/cassandra/full_backup.log"

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
for tool in jq aws openssl nodetool cqlsh xargs su find; do
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
LOG_FILE=$(jq -r '.full_backup_log_file' "$CONFIG_FILE")
LISTEN_ADDRESS=$(jq -r '.listen_address' "$CONFIG_FILE")
KEEP_DAYS=$(jq -r '.clearsnapshot_keep_days // 0' "$CONFIG_FILE")
UPLOAD_STREAMING=$(jq -r '.upload_streaming // "false"' "$CONFIG_FILE")
CASSANDRA_USER=$(jq -r '.cassandra_user // "cassandra"' "$CONFIG_FILE")
CASSANDRA_PASSWORD=$(jq -r '.cassandra_password // "null"' "$CONFIG_FILE")
SSL_ENABLED=$(jq -r '.ssl_enabled // "false"' "$CONFIG_FILE")
PARALLELISM=$(jq -r '.parallelism // 4' "$CONFIG_FILE")
S3_RETENTION_PERIOD=$(jq -r '.s3_retention_period // 0' "$CONFIG_FILE")
BACKUP_EXCLUDE_KEYSPACES=$(jq -r '.backup_exclude_keyspaces // []' "$CONFIG_FILE")
BACKUP_EXCLUDE_TABLES=$(jq -r '.backup_exclude_tables // []' "$CONFIG_FILE")
BACKUP_INCLUDE_ONLY_KEYSPACES=$(jq -r '.backup_include_only_keyspaces // []' "$CONFIG_FILE")
BACKUP_INCLUDE_ONLY_TABLES=$(jq -r '.backup_include_only_tables // []' "$CONFIG_FILE")
S3_OBJECT_LOCK_ENABLED=$(jq -r '.s3_object_lock_enabled // "false"' "$CONFIG_FILE")
S3_OBJECT_LOCK_MODE=$(jq -r '.s3_object_lock_mode // "GOVERNANCE"' "$CONFIG_FILE")
S3_OBJECT_LOCK_RETENTION=$(jq -r '.s3_object_lock_retention // 0' "$CONFIG_FILE")

# Validate sourced config
if [ -z "$S3_BUCKET_NAME" ] || [ -z "$CASSANDRA_DATA_DIR" ] || [ -z "$LOG_FILE" ]; then
  log_error "One or more required configuration values are missing from $CONFIG_FILE"
  exit 1
fi

# --- Static Configuration ---
BACKUP_TAG=$(date +'%Y-%m-%d-%H-%M') # NEW timestamp format
HOSTNAME=$(hostname -s)
# Derive temp dir from data dir to ensure it's on the correct large volume
BACKUP_TEMP_DIR="${CASSANDRA_DATA_DIR%/*}/backup_temp_$$"
LOCK_FILE="/tmp/cassandra_backup.lock"
ERROR_DIR="$BACKUP_TEMP_DIR/errors"
S3_OBJECT_LOCK_APPLICABLE="false"


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
    log_error "Aborting backup before taking a snapshot to prevent wasted effort."
    return 1
  fi
  log_success "AWS credentials are valid."
  return 0
}

# --- S3 Bucket Management Functions ---

check_existing_bucket_lock_config() {
    if [ "$S3_OBJECT_LOCK_ENABLED" != "true" ]; then
        S3_OBJECT_LOCK_APPLICABLE="false"
        return 0
    fi
    log_info "Verifying Object Lock configuration for existing bucket..."
    local lock_config
    lock_config=$(aws s3api get-object-lock-configuration --bucket "$S3_BUCKET_NAME" 2>/dev/null)
    if [ $? -ne 0 ]; then
        log_warn "Could not get S3 Object Lock configuration. This may be due to missing IAM permissions (s3:GetObjectLockConfiguration)."
        log_warn "Backup will proceed without applying Object Lock to uploads."
        S3_OBJECT_LOCK_APPLICABLE="false"
        return 0
    fi

    if echo "$lock_config" | jq -e '.ObjectLockConfiguration.ObjectLockEnabled == "Enabled"' > /dev/null; then
        log_success "Bucket '$S3_BUCKET_NAME' is correctly configured for Object Lock."
        S3_OBJECT_LOCK_APPLICABLE="true"
    else
        log_warn "S3_OBJECT_LOCK_ENABLED is true in config, but bucket '$S3_BUCKET_NAME' does not have Object Lock enabled."
        log_warn "Backup will proceed without applying Object Lock to uploads."
        S3_OBJECT_LOCK_APPLICABLE="false"
    fi
    return 0
}

manage_s3_lifecycle() {
    if [ "$BACKUP_BACKEND" != "s3" ] || [[ ! "$S3_RETENTION_PERIOD" =~ ^[1-9][0-9]*$ ]]; then
        log_info "S3 lifecycle management is skipped. Backend is not 's3' or retention period is not a positive number."
        return 0
    fi

    local policy_id="auto-expire-backups"
    log_info "Checking for S3 lifecycle policy '$policy_id' with retention of $S3_RETENTION_PERIOD days..."

    # Check if a policy with our ID already exists
    local existing_policy_json
    existing_policy_json=$(aws s3api get-bucket-lifecycle-configuration --bucket "$S3_BUCKET_NAME" 2>/dev/null || echo "")

    local existing_policy_days=""
    # Check if the returned string is valid JSON before trying to parse it
    if echo "$existing_policy_json" | jq -e . > /dev/null 2>&1; then
        existing_policy_days=$(echo "$existing_policy_json" | jq -r --arg ID "$policy_id" '.Rules[] | select(.ID == $ID) | .Expiration.Days // ""')
    fi

    if [[ "$existing_policy_days" == "$S3_RETENTION_PERIOD" ]]; then
        log_success "Correct lifecycle policy already in place. Nothing to do."
        return 0
    elif [[ -n "$existing_policy_days" ]]; then
        log_warn "A lifecycle policy with ID '$policy_id' exists but has a different retention ($existing_policy_days days). It will be updated."
    else
        log_info "No lifecycle policy named '$policy_id' found. A new one will be created."
    fi

    # Construct the lifecycle policy JSON
    local lifecycle_json
    lifecycle_json=$(jq -n \
        --arg ID "$policy_id" \
        --argjson DAYS "$S3_RETENTION_PERIOD" \
        '{
            "Rules": [
                {
                    "ID": $ID,
                    "Filter": {
                        "Prefix": ""
                    },
                    "Status": "Enabled",
                    "Expiration": {
                        "Days": $DAYS
                    }
                }
            ]
        }')

    log_info "Applying lifecycle policy to bucket '$S3_BUCKET_NAME'..."
    if ! aws s3api put-bucket-lifecycle-configuration --bucket "$S3_BUCKET_NAME" --lifecycle-configuration "$lifecycle_json"; then
        log_error "Failed to apply S3 lifecycle policy. Backups will still proceed, but will not be automatically deleted."
        # Do not fail the backup for this.
        return 0
    fi

    log_success "S3 lifecycle policy applied successfully."
}

ensure_s3_bucket_and_lifecycle() {
    if [ "$BACKUP_BACKEND" != "s3" ]; then
        return 0
    fi
    log_info "Checking if S3 bucket 's3://$S3_BUCKET_NAME' exists..."
    if aws s3api head-bucket --bucket "$S3_BUCKET_NAME" > /dev/null 2>&1; then
        log_success "S3 bucket already exists."
        check_existing_bucket_lock_config
        manage_s3_lifecycle
        return 0
    else
        log_warn "S3 bucket '$S3_BUCKET_NAME' does not exist. Attempting to create it..."
        
        local region
        region=$(aws configure get region 2>/dev/null || echo "us-east-1")

        local create_bucket_args=("--bucket" "$S3_BUCKET_NAME")
        if [ "$region" != "us-east-1" ]; then
            create_bucket_args+=("--create-bucket-configuration" "LocationConstraint=$region")
        fi

        local try_with_lock=false
        if [ "$S3_OBJECT_LOCK_ENABLED" == "true" ]; then
            create_bucket_args+=("--object-lock-enabled-for-bucket")
            log_info "Attempting to create bucket with Object Lock enabled."
            try_with_lock=true
        fi
        
        if ! aws s3api create-bucket "${create_bucket_args[@]}" >/dev/null 2>&1; then
            if [ "$try_with_lock" == "true" ]; then
                log_warn "Failed to create bucket with Object Lock. This may be due to missing IAM permissions (e.g., s3:PutBucketObjectLockConfiguration)."
                log_warn "Retrying to create the bucket without Object Lock..."
                
                local plain_create_args=("--bucket" "$S3_BUCKET_NAME")
                if [ "$region" != "us-east-1" ]; then
                   plain_create_args+=("--create-bucket-configuration" "LocationConstraint=$region")
                fi

                if ! aws s3api create-bucket "${plain_create_args[@]}"; then
                    log_error "Failed to create S3 bucket '$S3_BUCKET_NAME'."
                    return 1
                fi
                S3_OBJECT_LOCK_APPLICABLE="false"
            else
                 log_error "Failed to create S3 bucket '$S3_BUCKET_NAME'."
                 return 1
            fi
        else
            if [ "$try_with_lock" == "true" ]; then
                S3_OBJECT_LOCK_APPLICABLE="true"
            fi
        fi
        
        log_success "Successfully created S3 bucket '$S3_BUCKET_NAME'."
        manage_s3_lifecycle
        return 0
    fi
}

# --- Utility Functions ---

run_nodetool() {
    local cmd="nodetool $@"
    su -s /bin/bash "$CASSANDRA_USER" -c "$cmd"
}

cleanup_old_snapshots() {
    if [ -f "/var/lib/cleanup-disabled" ]; then
        log_warn "Snapshot cleanup is disabled via /var/lib/cleanup-disabled. Skipping."
        return 0
    fi

    if ! [[ "$KEEP_DAYS" =~ ^[0-9]+$ ]] || [ "$KEEP_DAYS" -le 0 ]; then
        log_info "Snapshot retention is not configured to a positive number ($KEEP_DAYS). Skipping old snapshot cleanup."
        return
    fi
    log_info "--- Starting Old Snapshot Cleanup (via direct file deletion) ---"
    log_info "Retention period: $KEEP_DAYS days"
    local all_snapshot_dirs
    all_snapshot_dirs=$(find "$CASSANDRA_DATA_DIR" -type d -path '*/snapshots/*' -prune -print 2>/dev/null || echo "")
    if [ -z "$all_snapshot_dirs" ]; then
        log_info "No snapshot directories found on filesystem. Nothing to clean up."
        log_info "--- Snapshot Cleanup Finished ---"
        return
    fi
    local unique_tags
    unique_tags=$(echo "$all_snapshot_dirs" | xargs -n 1 basename | sort -u)
    if [ -z "$unique_tags" ]; then
        log_info "Found snapshot parent directories, but no actual snapshots to evaluate."
        log_info "--- Snapshot Cleanup Finished ---"
        return
    fi
    log_info "Found snapshots to evaluate for cleanup."
    local cutoff_timestamp_days
    cutoff_timestamp_days=$(date -d "-$KEEP_DAYS days" +%s)
    for tag in $unique_tags; do
      local snapshot_timestamp=0
      local parsable_date=""
      if [[ "$tag" =~ ^adhoc_([0-9]{4}-[0-9]{2}-[0-9]{2})-([0-9]{2}-[0-9]{2}-[0-9]{2})$ ]]; then
          parsable_date="${BASH_REMATCH[1]} ${BASH_REMATCH[2]//-/:}"
      elif [[ "$tag" =~ ^([0-9]{4}-[0-9]{2}-[0-9]{2})-([0-9]{2}-[0-9]{2})$ ]]; then
          parsable_date="${BASH_REMATCH[1]} ${BASH_REMATCH[2]//-/:}"
      elif [[ "$tag" =~ ^adhoc_([0-9]{14})$ ]]; then
          local datetime_part=${BASH_REMATCH[1]}
          parsable_date="${datetime_part:0:4}-${datetime_part:4:2}-${datetime_part:6:2} ${datetime_part:8:2}:${datetime_part:10:2}:${datetime_part:12:2}"
      fi
      if [ -n "$parsable_date" ]; then
          snapshot_timestamp=$(date -d "$parsable_date" +%s 2>/dev/null || echo 0)
      fi
      if [[ "$snapshot_timestamp" -gt 0 && "$snapshot_timestamp" -lt "$cutoff_timestamp_days" ]]; then
        log_info "Deleting old snapshot directories with tag: $tag"
        find "$CASSANDRA_DATA_DIR" -type d -name "$tag" -path '*/snapshots/*' -exec rm -rf {} +
        log_success "Deletion complete for snapshot tag: $tag"
      elif [[ "$snapshot_timestamp" -eq 0 ]]; then
        log_warn "Could not parse date from snapshot tag '$tag'. Skipping cleanup for this tag."
      fi
    done
    log_info "--- Snapshot Cleanup Finished ---"
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

if ! check_aws_credentials; then
    exit 1
fi

if ! ensure_s3_bucket_and_lifecycle; then
    exit 1 # Fail fast if bucket creation or lifecycle management fails
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


# Run cleanup of old snapshots BEFORE taking a new one
cleanup_old_snapshots

log_info "--- Starting Granular Cassandra Snapshot Backup Process ---"
log_info "S3 Bucket: $S3_BUCKET_NAME"
log_info "Backup Timestamp (Tag): $BACKUP_TAG"
log_info "Streaming Mode: $UPLOAD_STREAMING"
log_info "Parallelism: $PARALLELISM"

# 1. Create temporary directories
mkdir -p "$BACKUP_TEMP_DIR" || { log_error "Failed to create temp backup directory on data volume."; exit 1; }
mkdir -p "$ERROR_DIR"

# 2. Take a node-local snapshot
log_info "Taking full snapshot with tag: $BACKUP_TAG..."
if ! run_nodetool snapshot -t "$BACKUP_TAG"; then
  log_error "Failed to take Cassandra snapshot. Aborting backup."
  exit 1
fi
log_success "Full snapshot taken successfully."

# 3. Archive and Upload, per-table
log_info "Discovering keyspaces and tables to back up..."
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

# --- Function to process a single table backup (for parallel execution) ---
process_table_backup() {
    local snapshot_dir="$1"
    
    # Required variables for the subshell
    S3_BUCKET_NAME=$(jq -r '.s3_bucket_name' "$CONFIG_FILE")
    BACKUP_BACKEND=$(jq -r '.backup_backend // "s3"' "$CONFIG_FILE")
    UPLOAD_STREAMING=$(jq -r '.upload_streaming // "false"' "$CONFIG_FILE")
    BACKUP_EXCLUDE_KEYSPACES=$(jq -r '.backup_exclude_keyspaces // []' "$CONFIG_FILE")
    BACKUP_EXCLUDE_TABLES=$(jq -r '.backup_exclude_tables // []' "$CONFIG_FILE")
    BACKUP_INCLUDE_ONLY_KEYSPACES=$(jq -r '.backup_include_only_keyspaces // []' "$CONFIG_FILE")
    BACKUP_INCLUDE_ONLY_TABLES=$(jq -r '.backup_include_only_tables // []' "$CONFIG_FILE")
    S3_OBJECT_LOCK_ENABLED=$(jq -r '.s3_object_lock_enabled // "false"' "$CONFIG_FILE")
    S3_OBJECT_LOCK_MODE=$(jq -r '.s3_object_lock_mode // "GOVERNANCE"' "$CONFIG_FILE")
    S3_OBJECT_LOCK_RETENTION=$(jq -r '.s3_object_lock_retention // 0' "$CONFIG_FILE")


    local path_without_prefix=${snapshot_dir#"$CASSANDRA_DATA_DIR/"}
    local ks_name
    ks_name=$(echo "$path_without_prefix" | cut -d'/' -f1)
    local table_dir_name
    table_dir_name=$(echo "$path_without_prefix" | cut -d'/' -f2)
    local table_name
    table_name=$(echo "$table_dir_name" | rev | cut -d'-' -f2- | rev)

    # --- Filtering Logic ---
    local full_table_name="${ks_name}.${table_name}"
    local include_mode=false
    if [[ $(echo "$BACKUP_INCLUDE_ONLY_KEYSPACES" | jq 'length') -gt 0 || $(echo "$BACKUP_INCLUDE_ONLY_TABLES" | jq 'length') -gt 0 ]]; then
        include_mode=true
    fi

    if [ "$include_mode" = true ]; then
        local should_include=false
        # Check if keyspace is in include list
        if echo "$BACKUP_INCLUDE_ONLY_KEYSPACES" | jq -e ".[] | select(. == \"$ks_name\")" > /dev/null; then
            should_include=true
        fi
        # Check if table is in include list
        if echo "$BACKUP_INCLUDE_ONLY_TABLES" | jq -e ".[] | select(. == \"$full_table_name\")" > /dev/null; then
            should_include=true
        fi

        if [ "$should_include" = false ]; then
            # This is too noisy for parallel execution
            return 0
        fi
    else # exclude mode
        # Check if keyspace is in exclude list
        if echo "$BACKUP_EXCLUDE_KEYSPACES" | jq -e ".[] | select(. == \"$ks_name\")" > /dev/null; then
            return 0
        fi
        # Check if table is in exclude list
        if echo "$BACKUP_EXCLUDE_TABLES" | jq -e ".[] | select(. == \"$full_table_name\")" > /dev/null; then
            return 0
        fi
    fi
    # --- End Filtering Logic ---

    local is_system_ks=false
    for included_ks in $INCLUDED_SYSTEM_KEYSPACES; do
        if [ "$ks_name" == "$included_ks" ]; then
            is_system_ks=true
            break
        fi
    done

    if [[ "$ks_name" == system* || "$ks_name" == dse* || "$ks_name" == solr* ]] && [ "$is_system_ks" = false ]; then
        # Silently return. The pre-scan will log this.
        return 0
    fi
    
    log_info "Backing up table: $ks_name.$table_name"
    
    if [ "$BACKUP_BACKEND" == "s3" ]; then
        if [ -f "/var/lib/upload-disabled" ]; then
            log_warn "S3 upload is disabled via /var/lib/upload-disabled. Skipping upload for $ks_name.$table_name."
            return 0
        fi
        
        local s3_path="s3://$S3_BUCKET_NAME/$HOSTNAME/$BACKUP_TAG/$ks_name/$table_name.tar.gz.enc"
        
        local object_lock_flags=()
        if [ "$S3_OBJECT_LOCK_ENABLED" == "true" ] && [ "$S3_OBJECT_LOCK_APPLICABLE" == "true" ] && [ "$S3_OBJECT_LOCK_RETENTION" -gt 0 ]; then
            local retain_until_date
            retain_until_date=$(date -d "+$S3_OBJECT_LOCK_RETENTION days" -u --iso-8601=seconds)
            object_lock_flags+=("--object-lock-mode" "$S3_OBJECT_LOCK_MODE" "--object-lock-retain-until-date" "$retain_until_date")
        fi

        if [ "$UPLOAD_STREAMING" = "true" ]; then
            nice -n 19 ionice -c 3 tar -C "$snapshot_dir" -c . | \
            gzip | \
            openssl enc -aes-256-cbc -salt -pbkdf2 -md sha256 -pass "file:$TMP_KEY_FILE" | \
            nice -n 19 ionice -c 3 aws s3 cp --quiet - "$s3_path" "${object_lock_flags[@]}"
            
            local pipeline_status=("${PIPESTATUS[@]}")
            if [ ${pipeline_status[0]} -ne 0 ] || [ ${pipeline_status[1]} -ne 0 ] || [ ${pipeline_status[2]} -ne 0 ] || [ ${pipeline_status[3]} -ne 0 ]; then
                log_error "Streaming backup failed for $ks_name.$table_name. tar: ${pipeline_status[0]}, gzip: ${pipeline_status[1]}, openssl: ${pipeline_status[2]}, aws: ${pipeline_status[3]}"
                touch "$ERROR_DIR/$ks_name.$table_name"
            else
                log_success "Successfully streamed backup for $ks_name.$table_name"
            fi
        else
            local local_tar_file="$BACKUP_TEMP_DIR/$ks_name.$table_name.tar.gz"
            local local_enc_file="$BACKUP_TEMP_DIR/$ks_name.$table_name.tar.gz.enc"

            if ! nice -n 19 ionice -c 3 tar -C "$snapshot_dir" -czf "$local_tar_file" .; then
                log_error "Failed to archive $ks_name.$table_name. Skipping."
                touch "$ERROR_DIR/$ks_name.$table_name"
                return 1
            fi
            if ! nice -n 19 ionice -c 3 openssl enc -aes-256-cbc -salt -pbkdf2 -md sha256 -in "$local_tar_file" -out "$local_enc_file" -pass "file:$TMP_KEY_FILE"; then
                log_error "Failed to encrypt $ks_name.$table_name. Skipping."
                touch "$ERROR_DIR/$ks_name.$table_name"
                rm -f "$local_tar_file"
                return 1
            fi
            if ! nice -n 19 ionice -c 3 aws s3 cp --quiet "$local_enc_file" "$s3_path" "${object_lock_flags[@]}"; then
                log_error "Failed to upload backup for $ks_name.$table_name"
                touch "$ERROR_DIR/$ks_name.$table_name"
            else
                log_success "Successfully uploaded backup for $ks_name.$table_name"
            fi
            rm -f "$local_tar_file" "$local_enc_file"
        fi
    else
        log_info "Backup backend is '$BACKUP_BACKEND', not 's3'. Skipping upload for $ks_name.$table_name."
    fi
}
export -f process_table_backup run_nodetool log_message log_info log_success log_warn log_error
export LOG_FILE CONFIG_FILE BACKUP_TEMP_DIR TMP_KEY_FILE INCLUDED_SYSTEM_KEYSPACES HOSTNAME BACKUP_TAG ERROR_DIR CASSANDRA_DATA_DIR CASSANDRA_USER
export BACKUP_EXCLUDE_KEYSPACES BACKUP_EXCLUDE_TABLES BACKUP_INCLUDE_ONLY_KEYSPACES BACKUP_INCLUDE_ONLY_TABLES
export RED GREEN YELLOW BLUE NC
export S3_OBJECT_LOCK_APPLICABLE


# --- Parallel backup execution ---
# Pre-scan and log skipped keyspaces to avoid noisy parallel logging
log_info "--- Pre-scanning for keyspaces to skip ---"
SKIPPED_KEYSPACES=$(mktemp)
find "$CASSANDRA_DATA_DIR" -mindepth 1 -maxdepth 1 -type d | while read -r ks_path; do
    ks_name=$(basename "$ks_path")
    is_system_ks=false
    for included_ks in $INCLUDED_SYSTEM_KEYSPACES; do
        if [ "$ks_name" == "$included_ks" ]; then
            is_system_ks=true
            break
        fi
    done
    if [[ "$ks_name" == system* || "$ks_name" == dse* || "$ks_name" == solr* ]] && [ "$is_system_ks" = false ]; then
        if ! grep -Fxq "$ks_name" "$SKIPPED_KEYSPACES"; then
            log_info "Skipping non-essential system keyspace backup: $ks_name"
            echo "$ks_name" >> "$SKIPPED_KEYSPACES"
        fi
    fi
done
rm -f "$SKIPPED_KEYSPACES"

log_info "--- Starting Parallel Backup of Tables ---"
find "$CASSANDRA_DATA_DIR" -type d -path "*/snapshots/$BACKUP_TAG" -not -empty -print0 | \
    xargs -0 -P "$PARALLELISM" -I {} bash -c 'process_table_backup "$1"' _ {}
log_info "--- Finished Parallel Backup of Tables ---"

TOTAL_TABLES_ATTEMPTED=$(find "$CASSANDRA_DATA_DIR" -type d -path "*/snapshots/$BACKUP_TAG" -not -empty | wc -l | tr -d ' ')
UPLOAD_ERRORS=$(find "$ERROR_DIR" -type f 2>/dev/null | wc -l | tr -d ' ')
TABLES_BACKED_UP_SUCCESS_COUNT=$((TOTAL_TABLES_ATTEMPTED - UPLOAD_ERRORS))


# 4. Dump cluster schema
SCHEMA_DUMP_FILE="$BACKUP_TEMP_DIR/schema.cql"
log_info "Dumping cluster schema to $SCHEMA_DUMP_FILE..."

cqlsh_command_parts=("cqlsh")
if [[ "$SSL_ENABLED" == "true" ]]; then
    cqlsh_command_parts+=("--ssl")
fi
if [[ "$CASSANDRA_PASSWORD" != "null" ]]; then
    cqlsh_command_parts+=("-u" "$CASSANDRA_USER" "-p" "$CASSANDRA_PASSWORD")
fi
cqlsh_command_parts+=("$LISTEN_ADDRESS")
cqlsh_command_parts+=("-e" "DESCRIBE SCHEMA")

if ! "${cqlsh_command_parts[@]}" > "$SCHEMA_DUMP_FILE"; then
    log_warn "Failed to dump schema. The backup will be incomplete for schema-only restores."
else
    log_success "Schema dumped successfully."
fi


# 5. Create Backup Manifest
MANIFEST_FILE="$BACKUP_TEMP_DIR/backup_manifest.json"
log_info "Creating backup manifest at $MANIFEST_FILE..."

# Tolerate failures in nodetool for manifest generation
CLUSTER_NAME=$(run_nodetool describecluster 2>/dev/null | grep 'Name:' | awk '{print $2}' || echo "Unknown")
if [ "$CLUSTER_NAME" == "Unknown" ]; then
    log_error "Could not get cluster name from 'nodetool describecluster'. Cannot create a valid manifest."
    exit 1
fi


if [ -n "$LISTEN_ADDRESS" ]; then
    NODE_IP="$LISTEN_ADDRESS"
else
    NODE_IP="$(hostname -i)"
fi

NODE_DC=$(run_nodetool info 2>/dev/null | grep -E '^\s*Data Center' | awk '{print $4}' || echo "Unknown")
NODE_RACK=$(run_nodetool info 2>/dev/null | grep -E '^\s*Rack' | awk '{print $3}' || echo "Unknown")

# Robust token gathering
NODE_TOKENS_RAW=$(run_nodetool ring 2>/dev/null | grep "\b$NODE_IP\b" | awk '{print $NF}' || echo "")
if [ -z "$NODE_TOKENS_RAW" ]; then
    log_error "Could not get tokens for node $NODE_IP from 'nodetool ring'. Cannot create a valid manifest."
    exit 1
fi
NODE_TOKENS=$(echo "$NODE_TOKENS_RAW" | tr '\n' ',' | sed 's/,$//')

# For the manifest, we will just list the count of tables
jq -n \
  --arg cluster_name "$CLUSTER_NAME" \
  --arg backup_id "$BACKUP_TAG" \
  --arg backup_type "full" \
  --arg timestamp "$(date --iso-8601=seconds)" \
  --arg node_ip "$NODE_IP" \
  --arg node_dc "$NODE_DC" \
  --arg node_rack "$NODE_RACK" \
  --arg tokens "$NODE_TOKENS" \
  --argjson tables_count "$TABLES_BACKED_UP_SUCCESS_COUNT" \
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
    "tables_backed_up_count": $tables_count
  }' > "$MANIFEST_FILE"

log_success "Manifest created successfully."

# 6. Upload Manifest, Schema and Schema to S3
if [ -f "/var/lib/upload-disabled" ]; then
    log_info "S3 upload is disabled via /var/lib/upload-disabled."
    log_info "Backup artifacts are available locally with tag: $BACKUP_TAG"
    log_info "Local snapshot will NOT be automatically cleared."
else
    object_lock_flags=()
    if [ "$S3_OBJECT_LOCK_ENABLED" == "true" ] && [ "$S3_OBJECT_LOCK_APPLICABLE" == "true" ] && [ "$S3_OBJECT_LOCK_RETENTION" -gt 0 ]; then
        retain_until_date=$(date -d "+$S3_OBJECT_LOCK_RETENTION days" -u --iso-8601=seconds)
        object_lock_flags+=("--object-lock-mode" "$S3_OBJECT_LOCK_MODE" "--object-lock-retain-until-date" "$retain_until_date")
    fi
    
    if [ "$BACKUP_BACKEND" == "s3" ]; then
        log_info "Uploading manifest file..."
        MANIFEST_S3_PATH="s3://$S3_BUCKET_NAME/$HOSTNAME/$BACKUP_TAG/backup_manifest.json"
        if ! aws s3 cp --quiet "$MANIFEST_FILE" "$MANIFEST_S3_PATH" "${object_lock_flags[@]}"; then
          log_error "Failed to upload manifest to S3. The backup is not properly indexed."
          exit 1
        fi
        log_success "Manifest uploaded successfully."
        
        log_info "Uploading schema mapping file..."
        SCHEMA_MAP_S3_PATH="s3://$S3_BUCKET_NAME/$HOSTNAME/$BACKUP_TAG/schema_mapping.json"
        if ! aws s3 cp --quiet "$SCHEMA_MAP_FILE" "$SCHEMA_MAP_S3_PATH" "${object_lock_flags[@]}"; then
            log_error "Failed to upload schema mapping file to S3."
        else
            log_success "Schema mapping file uploaded successfully."
        fi

        if [ -f "$SCHEMA_DUMP_FILE" ]; then
            log_info "Uploading schema dump..."
            SCHEMA_S3_PATH="s3://$S3_BUCKET_NAME/$HOSTNAME/$BACKUP_TAG/schema.cql"
            if ! aws s3 cp --quiet "$SCHEMA_DUMP_FILE" "$SCHEMA_S3_PATH" "${object_lock_flags[@]}"; then
                log_error "Failed to upload schema.cql to S3."
            else
                log_success "Schema dump uploaded successfully."
            fi
        fi

    else
        log_info "Backup backend is set to '$BACKUP_BACKEND', not 's3'. Skipping manifest and schema uploads."
        log_info "Local snapshot is available with tag: $BACKUP_TAG"
    fi
fi

if [ "$UPLOAD_ERRORS" -gt 0 ]; then
    log_error "--- Granular Cassandra Backup Process Finished with $UPLOAD_ERRORS ERRORS ---"
    log_error "Summary: $TABLES_BACKED_UP_SUCCESS_COUNT / $TOTAL_TABLES_ATTEMPTED tables backed up successfully."
    log_error "The following tables failed to back up:"
    for f in "$ERROR_DIR"/*; do
        log_error "  - $(basename "$f")"
    done
    exit 1
else
    log_success "--- Granular Cassandra Backup Process Finished Successfully ---"
    log_success "Summary: All $TOTAL_TABLES_ATTEMPTED tables backed up successfully."
fi

exit 0
