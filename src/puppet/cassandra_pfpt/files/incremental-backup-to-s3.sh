#!/bin/bash
# This file is managed by Puppet.
# Archives and uploads existing incremental backup files to S3, with modular execution.

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
LOG_FILE="/var/log/cassandra/incremental_backup.log"

log_message() {
  echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}
log_info() { log_message "${BLUE}$1${NC}"; }
log_success() { log_message "${GREEN}$1${NC}"; }
log_warn() { log_message "${YELLOW}$1${NC}"; }
log_error() { log_message "${RED}$1${NC}"; }

# --- Argument Parsing ---
MODE="default"
BACKUP_TAG_OVERRIDE=""

usage() {
    log_message "${YELLOW}Usage: $0 [MODE] [OPTIONS]${NC}"
    log_message "Manages the incremental backup process with modular steps."
    log_message ""
    log_message "Modes (mutually exclusive):"
    log_message "  --local-only                Archives incremental files to a local directory but does not upload to S3 or clean up source files."
    log_message "  --upload-only               Uploads a previously created local backup set to S3 and cleans up. Requires --tag."
    log_message "  (no mode)                   Default. Performs all steps: local backup, upload, and cleanup."
    log_message ""
    log_message "Options:"
    log_message "  --tag <timestamp>           The timestamp tag (YYYY-MM-DD-HH-MM) of the backup set to upload. Required for --upload-only."
    log_message "  -h, --help                  Show this help message."
    exit 1
}


while [[ "$#" -gt 0 ]]; do
    case $1 in
        --local-only) MODE="local_only" ;;
        --upload-only) MODE="upload_only" ;;
        --tag) BACKUP_TAG_OVERRIDE="$2"; shift ;;
        -h|--help) usage; exit 0 ;;
        *) log_error "Unknown parameter passed: $1"; usage; exit 1 ;;
    esac
    shift
done

if [ "$MODE" == "upload_only" ] && [ -z "$BACKUP_TAG_OVERRIDE" ]; then
    log_error "--tag <timestamp> is required for --upload-only mode."
    exit 1
fi

# --- Pre-flight Checks ---
for tool in jq aws openssl nodetool; do
    if ! command -v $tool &> /dev/null; then log_error "Required tool '$tool' is not installed or in PATH."; exit 1; fi
done
if [ ! -f "$CONFIG_FILE" ]; then log_error "Backup configuration file not found at $CONFIG_FILE"; exit 1; fi

# --- Source All Configuration from JSON ---
S3_BUCKET_NAME=$(jq -r '.s3_bucket_name' "$CONFIG_FILE")
BACKUP_BACKEND=$(jq -r '.backup_backend // "s3"' "$CONFIG_FILE")
CASSANDRA_DATA_DIR=$(jq -r '.cassandra_data_dir' "$CONFIG_FILE")
LOG_FILE=$(jq -r '.incremental_backup_log_file' "$CONFIG_FILE") # Overwrite default
LISTEN_ADDRESS=$(jq -r '.listen_address' "$CONFIG_FILE")
PARALLELISM=$(jq -r '.parallelism // 4' "$CONFIG_FILE")
CASSANDRA_USER=$(jq -r '.cassandra_user // "cassandra"' "$CONFIG_FILE")


# Validate sourced config
if [ -z "$S3_BUCKET_NAME" ] || [ -z "$CASSANDRA_DATA_DIR" ] || [ -z "$LOG_FILE" ]; then
  log_error "One or more required configuration values are missing from $CONFIG_FILE"
  exit 1
fi

# --- Define Paths and Static Vars ---
HOSTNAME=$(hostname -s)
BACKUP_TAG=${BACKUP_TAG_OVERRIDE:-$(date +'%Y-%m-%d-%H-%M')}
LOCAL_BACKUP_BASE_DIR="/var/lib/cassandra/local_backups"
LOCAL_BACKUP_DIR="$LOCAL_BACKUP_BASE_DIR/$BACKUP_TAG"
LOCK_FILE="/var/run/cassandra_backup.lock"
ERROR_DIR="$LOCAL_BACKUP_DIR/errors"

# --- Functions ---

do_local_backup() {
    log_info "--- Step 1: Creating Local Incremental Backup ---"
    
    local INCREMENTAL_DIRS_COUNT
    INCREMENTAL_DIRS_COUNT=$(find "$CASSANDRA_DATA_DIR" -type d -name "backups" -not -empty -print | wc -l)
    if [ "$INCREMENTAL_DIRS_COUNT" -eq 0 ]; then
        log_info "No new incremental backup files found. Nothing to do."
        return 2 # Special exit code to signal nothing to do.
    fi

    mkdir -p "$LOCAL_BACKUP_DIR" || { log_error "Failed to create local backup directory."; return 1; }
    mkdir -p "$ERROR_DIR"

    TABLES_BACKED_UP="[]"
    INCLUDED_SYSTEM_KEYSPACES="system_schema system_auth system_distributed"

    log_info "Archiving incremental files from source directories..."
    
    # Use a robust find and while loop to handle any filenames
    find "$CASSANDRA_DATA_DIR" -type d -name "backups" -not -empty -print0 | while IFS= read -r -d $'\0' backup_dir; do
        local relative_path
        relative_path=${backup_dir#"$CASSANDRA_DATA_DIR"/}
        local ks_name
        ks_name=$(echo "$relative_path" | cut -d'/' -f1)

        local is_system_ks=false
        for included_ks in $INCLUDED_SYSTEM_KEYSPACES; do
            if [ "$ks_name" == "$included_ks" ]; then is_system_ks=true; break; fi
        done
        if [[ "$ks_name" == system* || "$ks_name" == dse* || "$ks_name" == solr* ]] && [ "$is_system_ks" = false ]; then
            continue
        fi
        
        local table_dir_name
        table_dir_name=$(echo "$relative_path" | cut -d'/' -f2)
        local table_name
        table_name=$(echo "$table_dir_name" | rev | cut -d'-' -f2- | rev)
        
        log_info "Processing incremental backup for: $ks_name.$table_name"
        
        local local_tar_path="$LOCAL_BACKUP_DIR/$ks_name"
        mkdir -p "$local_tar_path"
        
        local local_tar_file="$local_tar_path/$table_name.tar.gz"
        local local_enc_file="$local_tar_path/$table_name.tar.gz.enc"

        if ! nice -n 19 ionice -c 3 tar -C "$backup_dir" -czf "$local_tar_file" .; then
            log_error "Failed to archive incremental backup for $ks_name.$table_name."
            touch "$ERROR_DIR/$ks_name.$table_name"
            continue
        fi

        if ! nice -n 19 ionice -c 3 openssl enc -aes-256-cbc -salt -pbkdf2 -md sha256 -in "$local_tar_file" -out "$local_enc_file" -pass "file:$TMP_KEY_FILE"; then
            log_error "Failed to encrypt incremental backup for $ks_name.$table_name."
            touch "$ERROR_DIR/$ks_name.$table_name"
            rm -f "$local_tar_file"
            continue
        fi
        rm -f "$local_tar_file" # Remove unencrypted archive
        TABLES_BACKED_UP=$(echo "$TABLES_BACKED_UP" | jq ". + [\"$ks_name/$table_name\"]")
    done

    log_info "Creating backup manifest..."
    local MANIFEST_FILE="$LOCAL_BACKUP_DIR/backup_manifest.json"
    local NODE_DC
    NODE_DC=$(su -s /bin/bash "$CASSANDRA_USER" -c "nodetool info" 2>/dev/null | grep -E '^\s*Data Center' | awk '{print $4}' || echo "Unknown")
    local NODE_RACK
    NODE_RACK=$(su -s /bin/bash "$CASSANDRA_USER" -c "nodetool info" 2>/dev/null | grep -E '^\s*Rack' | awk '{print $3}' || echo "Unknown")

    jq -n \
      --arg backup_id "$BACKUP_TAG" \
      --arg timestamp "$(date --iso-8601=seconds)" \
      --arg node_ip "$LISTEN_ADDRESS" \
      --arg node_dc "$NODE_DC" \
      --arg node_rack "$NODE_RACK" \
      --argjson tables "$TABLES_BACKED_UP" \
      '{
        "backup_id": $backup_id,
        "backup_type": "incremental",
        "timestamp_utc": $timestamp,
        "source_node": {
          "ip_address": $node_ip,
          "datacenter": $node_dc,
          "rack": $node_rack
        },
        "tables_backed_up": $tables
      }' > "$MANIFEST_FILE"

    log_success "--- Local Backup Finished. Stored at $LOCAL_BACKUP_DIR ---"
    return 0
}

do_upload() {
    if [ -f "/var/lib/upload-disabled" ]; then
        log_warn "S3 upload is disabled via /var/lib/upload-disabled. Skipping."
        return 0
    fi

    log_info "--- Step 2: Uploading Local Backup to S3 ---"
    
    if [ ! -d "$LOCAL_BACKUP_DIR" ]; then log_error "Local backup directory not found: $LOCAL_BACKUP_DIR"; return 1; fi
    if [ "$BACKUP_BACKEND" != "s3" ]; then log_warn "Backup backend is '$BACKUP_BACKEND', not 's3'. Skipping upload."; return 0; fi

    log_info "Uploading all backup files via aws s3 sync..."
    if ! aws s3 sync --quiet "$LOCAL_BACKUP_DIR" "s3://$S3_BUCKET_NAME/$HOSTNAME/$BACKUP_TAG/"; then
        log_error "aws s3 sync command failed. Upload is incomplete."
        return 1
    fi

    log_success "--- S3 Upload Finished Successfully ---"
    return 0
}

do_source_and_local_cleanup() {
    if [ -f "/var/lib/cleanup-disabled" ]; then
        log_warn "Source and local staging cleanup is disabled via /var/lib/cleanup-disabled. Skipping."
        return 0
    fi
    log_info "--- Step 3: Cleaning Up Source & Local Files ---"
    
    if [ ! -f "$LOCAL_BACKUP_DIR/backup_manifest.json" ]; then
        log_error "Manifest not found in local backup. Cannot safely clean up source files."
        return 1
    fi

    # Read the list of successfully backed up tables from the manifest
    jq -r '.tables_backed_up[]' "$LOCAL_BACKUP_DIR/backup_manifest.json" | while IFS= read -r table_spec; do
        ks_name=$(echo "$table_spec" | cut -d'/' -f1)
        table_name=$(echo "$table_spec" | cut -d'/' -f2)
        
        # Find the UUID-based directory name for the table.
        source_backup_dir=$(find "$CASSANDRA_DATA_DIR/$ks_name" -maxdepth 2 -type d -name "backups" -path "*/${table_name}-*/backups" 2>/dev/null | head -n 1)

        if [ -n "$source_backup_dir" ] && [ -d "$source_backup_dir" ]; then
            log_info "Cleaning incremental files for $ks_name/$table_name at $source_backup_dir"
            rm -f "${source_backup_dir:?}"/* # The :? adds protection against empty var
        else
            log_warn "Could not find source incremental directory for $ks_name/$table_name to clean up."
        fi
    done
    
    log_info "Removing local backup staging directory: $LOCAL_BACKUP_DIR"
    rm -rf "$LOCAL_BACKUP_DIR"

    log_success "--- Cleanup Finished ---"
}


# --- Main Logic ---

if [ "$(id -u)" -ne 0 ]; then log_error "This script must be run as root."; exit 1; fi

if [ -f "/var/lib/backup-disabled" ]; then
    log_info "Backup is disabled via /var/lib/backup-disabled. Aborting."
    exit 0
fi

if [ -f "$LOCK_FILE" ]; then
    OLD_PID=$(cat "$LOCK_FILE")
    if ps -p "$OLD_PID" > /dev/null; then log_warn "Backup process with PID $OLD_PID is still running. Exiting."; exit 1; fi
    log_warn "Stale lock file found for dead PID $OLD_PID. Removing."; rm -f "$LOCK_FILE"
fi

# Create lock file and temp key file, set trap for cleanup.
TMP_KEY_FILE=$(mktemp)
chmod 600 "$TMP_KEY_FILE"
echo $$ > "$LOCK_FILE"
trap 'rm -f "$LOCK_FILE"; rm -f "$TMP_KEY_FILE";' EXIT

ENCRYPTION_KEY=$(jq -r '.encryption_key' "$CONFIG_FILE")
if [ -z "$ENCRYPTION_KEY" ] || [ "$ENCRYPTION_KEY" == "null" ]; then log_error "encryption_key is empty or not found in $CONFIG_FILE"; exit 1; fi
echo -n "$ENCRYPTION_KEY" > "$TMP_KEY_FILE"


# --- Main Execution Flow ---
log_info "--- Starting Incremental Backup Manager (Mode: $MODE) ---"

case "$MODE" in
    "local_only")
        do_local_backup
        rc=$?
        if [ $rc -eq 2 ]; then
            exit 0 # Nothing to do
        elif [ $rc -ne 0 ]; then
            log_error "Local backup creation failed."
            exit 1
        fi
        log_info "Local incremental backup set created at $LOCAL_BACKUP_DIR. Source files and upload skipped."
        ;;
    "upload_only")
        if do_upload; then
            do_source_and_local_cleanup
        else
            log_error "Upload failed. Local backup and original incremental files are preserved for retry."
            exit 1
        fi
        ;;
    "default")
        do_local_backup
        local_backup_rc=$?
        if [ $local_backup_rc -eq 2 ]; then
            exit 0 # Nothing to do
        elif [ $local_backup_rc -ne 0 ]; then
            log_error "Local backup creation failed. Aborting."
            exit 1
        fi
        
        if do_upload; then
            do_source_and_local_cleanup
        else
            log_error "Upload failed. Local backup and original incremental files are preserved for retry."
            exit 1
        fi
        ;;
esac

log_info "--- Incremental Backup Process Finished ---"
exit 0
