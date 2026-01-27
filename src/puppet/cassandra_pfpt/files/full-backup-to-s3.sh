#!/bin/bash
# This file is managed by Puppet.
# Performs a full snapshot backup and uploads it to S3, with modular execution options.

set -euo pipefail

# This script needs to run with /bin/bash to support PIPESTATUS
if [ -z "$BASH_VERSION" ]; then
    exec /bin/bash "$0" "$@"
fi

# --- Static Configuration & Color Codes ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color
CONFIG_FILE="/etc/backup/config.json"
DEFAULT_LOG_FILE="/var/log/cassandra/full_backup.log"
LOCAL_BACKUP_ROOT_DIR="/var/lib/cassandra/local_backups"
LOCK_FILE="/var/run/cassandra_backup.lock"

# --- Logging Initialization ---
LOG_FILE="$DEFAULT_LOG_FILE" # Can be overwritten by config

log_message() {
  echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}
log_info() { log_message "${BLUE}$1${NC}"; }
log_success() { log_message "${GREEN}$1${NC}"; }
log_warn() { log_message "${YELLOW}$1${NC}"; }
log_error() { log_message "${RED}$1${NC}"; }

# --- Usage Function ---
usage() {
    log_message "Usage: $0 [MODE] [OPTIONS]"
    log_message "Performs a full snapshot backup of Cassandra."
    log_message ""
    log_message "MODES (mutually exclusive):"
    log_message "  <default>             (No mode flag) Performs cleanup, local backup, and S3 upload in sequence."
    log_message "  --cleanup-only        Only runs the cleanup of old local snapshots on the node."
    log_message "  --local-only          Performs snapshot and local archiving, but does not upload to S3. Backup is stored in ${LOCAL_BACKUP_ROOT_DIR}."
    log_message "  --upload-only         Uploads a pre-existing local backup from ${LOCAL_BACKUP_ROOT_DIR} to S3. Requires --tag."
    log_message ""
    log_message "OPTIONS:"
    log_message "  --tag <timestamp>     Specify a backup tag (YYYY-MM-DD-HH-MM). Required for --upload-only."
    log_message "  -h, --help            Show this help message."
}

# --- Parse Arguments ---
MODE="default"
BACKUP_TAG_OVERRIDE=""

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --cleanup-only) MODE="cleanup_only"; shift ;;
        --local-only) MODE="local_only"; shift ;;
        --upload-only) MODE="upload_only"; shift ;;
        --tag) BACKUP_TAG_OVERRIDE="$2"; shift 2;;
        -h|--help) usage; exit 0 ;;
        *) log_error "Unknown parameter: $1"; usage; exit 1 ;;
    esac
done

# --- Pre-flight Checks ---
if [ "$(id -u)" -ne 0 ]; then
  log_error "This script must be run as root."
  exit 1
fi
for tool in jq aws openssl nodetool cqlsh xargs su find; do
    if ! command -v $tool &> /dev/null; then
        log_error "Required tool '$tool' is not installed or in PATH."
        exit 1
    fi
done
if [ ! -f "$CONFIG_FILE" ]; then
  log_error "Backup configuration file not found at $CONFIG_FILE"
  exit 1
fi

# --- Source Configuration from JSON ---
S3_BUCKET_NAME=$(jq -r '.s3_bucket_name' "$CONFIG_FILE")
BACKUP_BACKEND=$(jq -r '.backup_backend // "s3"' "$CONFIG_FILE")
CASSANDRA_DATA_DIR=$(jq -r '.cassandra_data_dir' "$CONFIG_FILE")
LOG_FILE=$(jq -r '.full_backup_log_file // "'"$DEFAULT_LOG_FILE"'"' "$CONFIG_FILE")
LISTEN_ADDRESS=$(jq -r '.listen_address' "$CONFIG_FILE")
KEEP_DAYS=$(jq -r '.clearsnapshot_keep_days // 0' "$CONFIG_FILE")
CASSANDRA_USER=$(jq -r '.cassandra_user // "cassandra"' "$CONFIG_FILE")
CASSANDRA_PASSWORD=$(jq -r '.cassandra_password // "null"' "$CONFIG_FILE")
SSL_ENABLED=$(jq -r '.ssl_enabled // "false"' "$CONFIG_FILE")
PARALLELISM=$(jq -r '.parallelism // 4' "$CONFIG_FILE")
S3_RETENTION_PERIOD=$(jq -r '.s3_retention_period // 0' "$CONFIG_FILE")
HOSTNAME=$(hostname -s)
JVM_OPTS_FILE=$(jq -r '.jvm_opts_file' "$CONFIG_FILE")
JMX_PASS_FILE=$(jq -r '.jmx_password_file' "$CONFIG_FILE")


# Validate sourced config
if [ -z "$S3_BUCKET_NAME" ] || [ -z "$CASSANDRA_DATA_DIR" ] || [ -z "$LOG_FILE" ]; then
  log_error "One or more required configuration values are missing from $CONFIG_FILE"
  exit 1
fi

# --- JMX Auth Setup ---
NODETOOL_CMD="nodetool"
if [ -f "$JVM_OPTS_FILE" ] && grep -q -- '-Dcom.sun.management.jmxremote.authenticate=true' "$JVM_OPTS_FILE"; then
    log_info "JMX authentication is enabled. Configuring nodetool command."
    if [ -f "$JMX_PASS_FILE" ]; then
        JMX_USER=$(awk '/monitorRole/ {print $1}' "$JMX_PASS_FILE" 2>/dev/null)
        JMX_PASS=$(awk '/monitorRole/ {print $2}' "$JMX_PASS_FILE" 2>/dev/null)
        if [ -n "$JMX_USER" ] && [ -n "$JMX_PASS" ]; then
             NODETOOL_CMD="nodetool -u $JMX_USER -pw $JMX_PASS"
             log_info "Using JMX user 'monitorRole' for nodetool commands."
        else
            log_warn "Could not find 'monitorRole' credentials in $JMX_PASS_FILE. Nodetool commands might fail."
        fi
    else
        log_warn "JMX auth is on, but password file $JMX_PASS_FILE not found. Nodetool commands might fail."
    fi
fi

# --- Function Declarations ---

run_nodetool() {
    # This function runs a nodetool command as the cassandra user.
    # It takes the full nodetool command string (e.g., "listsnapshots" or "snapshot -t mytag") as arguments.
    # The base $NODETOOL_CMD (with JMX credentials) is prepended automatically.
    
    local full_command_to_run="$NODETOOL_CMD $*"
    # Using su to run as the correct user ensures the command has the right environment
    su -s /bin/bash "$CASSANDRA_USER" -c "$full_command_to_run"
    return $?
}

cleanup_old_snapshots() {
    if ! [[ "$KEEP_DAYS" =~ ^[0-9]+$ ]] || [ "$KEEP_DAYS" -le 0 ]; then
        log_info "Snapshot retention is not configured to a positive number ($KEEP_DAYS). Skipping old snapshot cleanup."
        return
    fi

    log_info "--- Starting Old Snapshot Cleanup via Direct File Deletion ---"
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
      
      # Try parsing new adhoc format 'adhoc_YYYY-MM-DD-HH-MM-SS'
      if [[ "$tag" =~ ^adhoc_([0-9]{4}-[0-9]{2}-[0-9]{2})-([0-9]{2}-[0-9]{2}-[0-9]{2})$ ]]; then
          parsable_date="${BASH_REMATCH[1]} ${BASH_REMATCH[2]//-/:}"
      # Try parsing automated backup format 'YYYY-MM-DD-HH-MM'
      elif [[ "$tag" =~ ^([0-9]{4}-[0-9]{2}-[0-9]{2})-([0-9]{2}-[0-9]{2})$ ]]; then
          parsable_date="${BASH_REMATCH[1]} ${BASH_REMATCH[2]//-/:}"
      # Try parsing legacy adhoc format 'adhoc_YYYYMMDDHHMMSS'
      elif [[ "$tag" =~ ^adhoc_([0-9]{14})$ ]]; then
          local datetime_part=${BASH_REMATCH[1]}
          parsable_date="${datetime_part:0:4}-${datetime_part:4:2}-${datetime_part:6:2} ${datetime_part:8:2}:${datetime_part:10:2}:${datetime_part:12:2}"
      fi
      
      if [ -n "$parsable_date" ]; then
          snapshot_timestamp=$(date -d "$parsable_date" +%s 2>/dev/null || echo 0)
      fi

      if [[ "$snapshot_timestamp" -gt 0 ]]; then
        if [ "$snapshot_timestamp" -lt "$cutoff_timestamp_days" ]; then
          log_info "Deleting old snapshot directories with tag: $tag"
          # Find all directories with this name under any 'snapshots' directory and delete them
          find "$CASSANDRA_DATA_DIR" -type d -name "$tag" -path '*/snapshots/*' -exec rm -rf {} +
          log_success "Deletion complete for snapshot tag: $tag"
        fi
      else
        log_warn "Could not parse date from snapshot tag '$tag'. Skipping cleanup for this tag."
      fi
    done
    log_info "--- Snapshot Cleanup Finished ---"
}

check_aws_credentials() {
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

manage_s3_lifecycle() {
    if [ "$BACKUP_BACKEND" != "s3" ] || [[ ! "$S3_RETENTION_PERIOD" =~ ^[1-9][0-9]*$ ]]; then
        log_info "S3 lifecycle management is skipped. Backend is not 's3' or retention period is not a positive number."
        return 0
    fi

    local policy_id="auto-expire-backups"
    log_info "Checking for S3 lifecycle policy '$policy_id' with retention of $S3_RETENTION_PERIOD days..."

    local existing_policy_json
    existing_policy_json=$(aws s3api get-bucket-lifecycle-configuration --bucket "$S3_BUCKET_NAME" 2>/dev/null || echo "")

    local existing_policy_days=""
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
        manage_s3_lifecycle
        return 0
    else
        log_warn "S3 bucket '$S3_BUCKET_NAME' does not exist. Attempting to create it..."
        if aws s3 mb "s3://$S3_BUCKET_NAME"; then
            log_success "Successfully created S3 bucket '$S3_BUCKET_NAME'."
            manage_s3_lifecycle
            return 0
        else
            log_error "Failed to create S3 bucket '$S3_BUCKET_NAME'."
            log_error "Please check your AWS permissions (s3:CreateBucket) and ensure the bucket name is globally unique."
            return 1
        fi
    fi
}

do_cleanup() {
    log_info "--- Step 1: Cleaning up old local snapshots ---"
    cleanup_old_snapshots
    log_success "Snapshot cleanup finished."
}

do_local_backup() {
    log_info "--- Step 2: Performing local snapshot and backup ---"
    
    # 1. Setup backup-specific variables
    export BACKUP_TAG=${BACKUP_TAG_OVERRIDE:-$(date +'%Y-%m-%d-%H-%M')}
    export LOCAL_BACKUP_DIR="${LOCAL_BACKUP_ROOT_DIR}/${BACKUP_TAG}"
    export ERROR_DIR="${LOCAL_BACKUP_DIR}/.errors"
    
    if [ -d "$LOCAL_BACKUP_DIR" ]; then
        log_error "Local backup directory ${LOCAL_BACKUP_DIR} already exists. Aborting to prevent data loss."
        exit 1
    fi
    mkdir -p "$LOCAL_BACKUP_DIR" "$ERROR_DIR"

    # 2. Take snapshot
    log_info "Taking full snapshot with tag: $BACKUP_TAG..."
    if ! run_nodetool "snapshot -t \"$BACKUP_TAG\""; then
      log_error "Failed to take Cassandra snapshot. Aborting backup."
      rm -rf "$LOCAL_BACKUP_DIR"
      exit 1
    fi
    log_success "Full snapshot taken successfully."

    # 3. Generate schema mapping
    log_info "Generating schema-to-directory mapping..."
    local SCHEMA_MAP_FILE="$LOCAL_BACKUP_DIR/schema_mapping.json"
    local SCHEMA_MAP="{}"
    local INCLUDED_SYSTEM_KEYSPACES="system_schema system_auth system_distributed"
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
    log_success "Schema mapping generated."

    # 4. Define and export the process_table_backup function
    process_table_backup() {
        local snapshot_dir="$1"
        
        local path_without_prefix=${snapshot_dir#"$CASSANDRA_DATA_DIR/"}
        local ks_name=$(echo "$path_without_prefix" | cut -d'/' -f1)
        local table_dir_name=$(echo "$path_without_prefix" | cut -d'/' -f2)
        local table_name=$(echo "$table_dir_name" | rev | cut -d'-' -f2- | rev)

        local is_system_ks=false
        for included_ks in $INCLUDED_SYSTEM_KEYSPACES; do
            if [ "$ks_name" == "$included_ks" ]; then is_system_ks=true; break; fi
        done
        if [[ "$ks_name" == system* || "$ks_name" == dse* || "$ks_name" == solr* ]] && [ "$is_system_ks" = false ]; then return 0; fi
        
        log_info "Archiving table: $ks_name.$table_name"
        local local_enc_file="${LOCAL_BACKUP_DIR}/${ks_name}.${table_name}.tar.gz.enc"
        
        if ! (nice -n 19 ionice -c 3 tar -C "$snapshot_dir" -c . | gzip | openssl enc -aes-256-cbc -salt -pbkdf2 -md sha256 -out "$local_enc_file" -pass "file:$TMP_KEY_FILE"); then
             log_error "Failed to create local encrypted archive for $ks_name.$table_name"
             touch "${ERROR_DIR}/${ks_name}.${table_name}"
        else
             log_success "Created local archive for $ks_name.$table_name"
        fi
    }
    export -f process_table_backup log_message log_info log_success log_warn log_error
    export RED GREEN YELLOW BLUE NC LOG_FILE CASSANDRA_DATA_DIR LOCAL_BACKUP_DIR TMP_KEY_FILE ERROR_DIR

    # 5. Run parallel backup
    log_info "--- Starting Parallel Archiving of Tables to ${LOCAL_BACKUP_DIR} ---"
    find "$CASSANDRA_DATA_DIR" -type d -path "*/snapshots/$BACKUP_TAG" -not -empty -print0 | \
        xargs -0 -P "$PARALLELISM" -I {} bash -c 'process_table_backup "{}"'

    # 6. Check for errors
    local archive_errors=$(find "$ERROR_DIR" -type f 2>/dev/null | wc -l | tr -d ' ')
    if [ "$archive_errors" -gt 0 ]; then
        log_error "Local backup process FAILED for ${archive_errors} tables. Check logs above. Aborting."
        exit 1
    fi
    log_success "All tables archived locally."

    # 7. Dump schema.cql
    local SCHEMA_DUMP_FILE="$LOCAL_BACKUP_DIR/schema.cql"
    log_info "Dumping cluster schema to $SCHEMA_DUMP_FILE..."
    local cqlsh_command_parts=("cqlsh" "$LISTEN_ADDRESS")
    if [[ "$SSL_ENABLED" == "true" ]]; then cqlsh_command_parts+=("--ssl"); fi
    if [[ "$CASSANDRA_PASSWORD" != "null" ]]; then cqlsh_command_parts+=("-u" "$CASSANDRA_USER" "-p" "$CASSANDRA_PASSWORD"); fi
    cqlsh_command_parts+=("-e" "DESCRIBE SCHEMA")
    if ! "${cqlsh_command_parts[@]}" > "$SCHEMA_DUMP_FILE"; then
        log_warn "Failed to dump schema. The backup will be incomplete for schema-only restores."
    else
        log_success "Schema dumped successfully."
    fi

    # 8. Create manifest
    local MANIFEST_FILE="$LOCAL_BACKUP_DIR/backup_manifest.json"
    log_info "Creating backup manifest at $MANIFEST_FILE..."
    local CLUSTER_NAME=$(run_nodetool describecluster 2>/dev/null | grep 'Name:' | awk '{print $2}' || echo "Unknown")
    if [ "$CLUSTER_NAME" == "Unknown" ]; then log_error "Could not get cluster name. Cannot create a valid manifest."; exit 1; fi
    local NODE_IP=${LISTEN_ADDRESS:-$(hostname -i)}
    local NODE_DC=$(run_nodetool info 2>/dev/null | grep -E '^\s*Data Center' | awk '{print $4}' || echo "Unknown")
    local NODE_RACK=$(run_nodetool info 2>/dev/null | grep -E '^\s*Rack' | awk '{print $3}' || echo "Unknown")
    local NODE_TOKENS_RAW=$(run_nodetool ring 2>/dev/null | grep "\b$NODE_IP\b" | awk '{print $NF}' || echo "")
    if [ -z "$NODE_TOKENS_RAW" ]; then log_error "Could not get tokens. Cannot create a valid manifest."; exit 1; fi
    local NODE_TOKENS=$(echo "$NODE_TOKENS_RAW" | tr '\n' ',' | sed 's/,$//')
    local total_tables_attempted=$(find "$CASSANDRA_DATA_DIR" -type d -path "*/snapshots/$BACKUP_TAG" -not -empty | wc -l | tr -d ' ')
    jq -n \
      --arg cluster_name "$CLUSTER_NAME" \
      --arg backup_id "$BACKUP_TAG" \
      --arg backup_type "full" \
      --arg timestamp "$(date --iso-8601=seconds)" \
      --arg node_ip "$NODE_IP" \
      --arg node_dc "$NODE_DC" \
      --arg node_rack "$NODE_RACK" \
      --arg tokens "$NODE_TOKENS" \
      --argjson tables_count "$total_tables_attempted" \
      '{
        "cluster_name": $cluster_name, "backup_id": $backup_id, "backup_type": $backup_type, "timestamp_utc": $timestamp,
        "source_node": {"ip_address": $node_ip, "datacenter": $node_dc, "rack": $node_rack, "tokens": ($tokens | split(","))},
        "tables_backed_up_count": $tables_count
      }' > "$MANIFEST_FILE"
    log_success "Manifest created successfully."
    
    log_success "Local backup completed successfully. Find it at: ${LOCAL_BACKUP_DIR}"
}

do_upload() {
    log_info "--- Step 3: Uploading backup to S3 ---"
    
    export BACKUP_TAG=${BACKUP_TAG_OVERRIDE:-$BACKUP_TAG}
    if [ -z "$BACKUP_TAG" ]; then
        log_error "Backup tag is not set. This should not happen in default or upload-only mode."
        exit 1
    fi
    
    local local_backup_dir="${LOCAL_BACKUP_ROOT_DIR}/${BACKUP_TAG}"
    if [ ! -d "$local_backup_dir" ]; then
        log_error "Local backup directory not found: ${local_backup_dir}"
        exit 1
    fi

    if [ "$BACKUP_BACKEND" != "s3" ]; then log_info "Backup backend is not 's3', skipping upload."; return; fi
    if [ -f "/var/lib/upload-disabled" ]; then log_info "S3 upload is disabled via /var/lib/upload-disabled. Skipping."; return; fi
    if ! check_aws_credentials || ! ensure_s3_bucket_and_lifecycle; then
        log_error "Pre-flight AWS checks failed. Aborting upload."
        exit 1
    fi

    log_info "Starting upload of backup ${BACKUP_TAG} to s3://${S3_BUCKET_NAME}/${HOSTNAME}/${BACKUP_TAG}/"

    if ! aws s3 sync "$local_backup_dir" "s3://${S3_BUCKET_NAME}/${HOSTNAME}/${BACKUP_TAG}/" --exclude ".errors/*" --quiet; then
        log_error "S3 sync failed for backup tag ${BACKUP_TAG}. The local backup is preserved at ${local_backup_dir} for retry."
        exit 1
    fi
    
    log_success "Backup successfully uploaded to S3."

    log_info "Cleaning up local backup directory: ${local_backup_dir}"
    rm -rf "$local_backup_dir"
}

# --- Main Execution Block ---

# Check for disabled flag first
if [ -f "/var/lib/backup-disabled" ]; then
    log_info "Backup is disabled via /var/lib/backup-disabled. Aborting."
    exit 0
fi

# Manage lock file
if [ -f "$LOCK_FILE" ]; then
    OLD_PID=$(cat "$LOCK_FILE")
    if ps -p "$OLD_PID" > /dev/null; then
        log_warn "Backup process with PID $OLD_PID is still running. Exiting."
        exit 1
    else
        log_warn "Stale lock file found for dead PID $OLD_PID. Removing."
        rm -f "$LOCK_FILE"
    fi
fi
echo $$ > "$LOCK_FILE"

# Prepare encryption key and set trap
TMP_KEY_FILE=$(mktemp)
chmod 600 "$TMP_KEY_FILE"
trap 'rm -f "$LOCK_FILE"; rm -f "$TMP_KEY_FILE"' EXIT
ENCRYPTION_KEY=$(jq -r '.encryption_key' "$CONFIG_FILE")
if [ -z "$ENCRYPTION_KEY" ] || [ "$ENCRYPTION_KEY" == "null" ]; then
    log_error "encryption_key is empty or not found in $CONFIG_FILE"
    exit 1
fi
echo -n "$ENCRYPTION_KEY" > "$TMP_KEY_FILE"

# Export variables needed by subshells
export INCLUDED_SYSTEM_KEYSPACES="system_schema system_auth system_distributed"

# Route to the correct logic based on MODE
case $MODE in
    "cleanup_only")
        log_info "--- Running in Cleanup-Only Mode ---"
        do_cleanup
        log_success "Mode finished successfully."
        ;;
    "upload_only")
        log_info "--- Running in Upload-Only Mode ---"
        if [ -z "$BACKUP_TAG_OVERRIDE" ]; then log_error "--tag is required for --upload-only mode."; usage; exit 1; fi
        do_upload
        log_success "Mode finished successfully."
        ;;
    "local_only")
        log_info "--- Running in Local-Only Mode ---"
        do_cleanup
        do_local_backup
        log_success "Mode finished successfully."
        ;;
    "default")
        log_info "--- Running in Default Mode (Cleanup, Backup, Upload) ---"
        do_cleanup
        do_local_backup
        do_upload
        log_success "Mode finished successfully."
        ;;
esac

exit 0
