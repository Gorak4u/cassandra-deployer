#!/bin/bash
# Restores a Cassandra node from backups in S3 to a specific point in time.
# This script can combine a full backup with subsequent incremental backups.
# Supports full node restore, granular keyspace/table restore.

set -euo pipefail

# --- Color Codes ---
RED='\e[0;31m'
GREEN='\e[0;32m'
YELLOW='\e[1;33m'
BLUE='\e[0;34m'
CYAN='\e[0;36m'
BOLD='\e[1m'
NC='\e[0m' # No Color

# --- Configuration & Input ---
CONFIG_FILE="/etc/backup/config.json"
# Define a default log file path in case config loading fails, ensuring early errors are logged.
RESTORE_LOG_FILE="/var/log/cassandra/restore.log"

log_message() {
    # This version of log_message does not add colors, as the caller functions will.
    echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$RESTORE_LOG_FILE"
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
# Run these checks as early as possible so any failure is logged.
if [ "$(id -u)" -ne 0 ]; then
    log_error "This script must be run as root."
    exit 1
fi

for tool in jq aws sstableloader openssl pgrep ps cqlsh rsync xargs /usr/local/bin/disk-health-check.sh; do
    if ! command -v $tool &>/dev/null; then
        log_error "Required tool '$tool' is not installed or not in PATH."
        exit 1
    fi
done

if [ ! -f "$CONFIG_FILE" ]; then
    log_error "Backup configuration file not found at $CONFIG_FILE"
    exit 1
fi

# --- Variables defined after initial checks ---
HOSTNAME=$(hostname -s)
TEMP_RESTORE_DIR="" # Global variable to track the temporary directory

# --- Usage ---
usage() {
    log_message "${YELLOW}Usage: $0 [MODE] [OPTIONS]${NC}"
    log_message ""
    log_message "Modes (choose one):"
    log_message "  --list-backups                List all available backup sets for a host."
    log_message "  --show-restore-chain          Show the specific backup files that would be used for a restore to a given date."
    log_message "  --full-restore                Performs a full, destructive restore of the entire node."
    log_message "  --schema-only                 Downloads only the schema definition (schema.cql) from the latest full backup."
    log_message "  --download-only               Downloads data for a specific keyspace/table, but does not load it into Cassandra."
    log_message "  --download-and-restore        Downloads and restores data for a specific keyspace/table into the live cluster."
    log_message ""
    log_message "Options:"
    log_message "  --date <timestamp>            Required for all restore modes. Target UTC timestamp ('YYYY-MM-DD-HH-MM')."
    log_message "  --keyspace <ks>               Required for --download-only and --download-and-restore modes."
    log_message "  --table <table>               Optional. Narrows the granular restore to a single table."
    log_message "  --source-host <hostname>      Specify the source host for the backup. Defaults to the current hostname."
    log_message "  --s3-bucket <name>            Override the S3 bucket from config.json."
    log_message "  --yes                         Skips all interactive confirmation prompts. Use with caution."
    exit 1
}


# --- Source configuration from JSON ---
S3_BUCKET_NAME=$(jq -r '.s3_bucket_name' "$CONFIG_FILE")
CASSANDRA_DATA_DIR=$(jq -r '.cassandra_data_dir' "$CONFIG_FILE")
CASSANDRA_CONF_DIR=$(jq -r '.cassandra_conf_dir' "$CONFIG_FILE")
CASSANDRA_COMMITLOG_DIR=$(jq -r '.commitlog_dir' "$CONFIG_FILE")
CASSANDRA_CACHES_DIR=$(jq -r '.saved_caches_dir' "$CONFIG_FILE")
LISTEN_ADDRESS=$(jq -r '.listen_address' "$CONFIG_FILE")
SEEDS=$(jq -r '.seeds_list | join(",")' "$CONFIG_FILE")
CASSANDRA_USER=$(jq -r '.cassandra_user // "cassandra"' "$CONFIG_FILE")
CASSANDRA_PASSWORD=$(jq -r '.cassandra_password // "null"' "$CONFIG_FILE")
SSL_ENABLED=$(jq -r '.ssl_enabled // "false"' "$CONFIG_FILE")
BACKUP_BACKEND=$(jq -r '.backup_backend // "s3"' "$CONFIG_FILE")
PARALLELISM=$(jq -r '.parallelism // 4' "$CONFIG_FILE")

# Validate essential configuration
if [ -z "$CASSANDRA_CONF_DIR" ] || [ "$CASSANDRA_CONF_DIR" == "null" ]; then log_error "'cassandra_conf_dir' is not set or invalid in $CONFIG_FILE."; exit 1; fi
if [ -z "$CASSANDRA_DATA_DIR" ] || [ "$CASSANDRA_DATA_DIR" == "null" ]; then log_error "'cassandra_data_dir' is not set in $CONFIG_FILE."; exit 1; fi
if [ -z "$CASSANDRA_COMMITLOG_DIR" ] || [ "$CASSANDRA_COMMITLOG_DIR" == "null" ]; then log_error "'commitlog_dir' is not set in $CONFIG_FILE."; exit 1; fi
if [ -z "$CASSANDRA_CACHES_DIR" ] || [ "$CASSANDRA_CACHES_DIR" == "null" ]; then log_error "'saved_caches_dir' is not set in $CONFIG_FILE."; exit 1; fi
if [ -z "$LISTEN_ADDRESS" ] || [ "$LISTEN_ADDRESS" == "null" ]; then log_error "'listen_address' is not set in $CONFIG_FILE."; exit 1; fi


# Derive restore paths from the main data directory parameter
RESTORE_BASE_PATH="${CASSANDRA_DATA_DIR%/*}" # e.g., /var/lib/cassandra
DOWNLOAD_ONLY_PATH="${RESTORE_BASE_PATH}/restore_download"


# Determine node list for sstableloader. Use seeds if available, otherwise localhost.
if [ -n "$SEEDS" ]; then
    LOADER_NODES="$SEEDS"
else
    LOADER_NODES="$LISTEN_ADDRESS"
fi

# --- Argument Parsing ---
TARGET_DATE=""
KEYSPACE_NAME=""
TABLE_NAME=""
MODE=""
RESTORE_ACTION=""
AUTO_APPROVE=false
S3_BUCKET_OVERRIDE=""
SOURCE_HOST_OVERRIDE=""

if [ "$#" -eq 0 ]; then
    usage
fi

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --date) TARGET_DATE="$2"; shift ;;
        --keyspace) KEYSPACE_NAME="$2"; shift ;;
        --table) TABLE_NAME="$2"; shift ;;
        --s3-bucket) S3_BUCKET_OVERRIDE="$2"; shift ;;
        --source-host) SOURCE_HOST_OVERRIDE="$2"; shift ;;
        --full-restore) MODE="full" ;;
        --download-only) MODE="download_only" ;;
        --download-and-restore) MODE="download_and_restore" ;;
        --schema-only) MODE="schema_only" ;;
        --list-backups) MODE="list";;
        --show-restore-chain) MODE="chain";;
        --yes) AUTO_APPROVE=true ;;
        *) log_error "Unknown parameter passed: $1"; usage ;;
    esac
    shift
done

# Validate arguments
if [ -z "$MODE" ]; then
    log_error "No mode specified. You must choose one of: --list-backups, --show-restore-chain, --full-restore, --schema-only, --download-only, --download-and-restore"
    usage
fi

if [[ "$MODE" == "chain" || "$MODE" == "full" || "$MODE" == "download_only" || "$MODE" == "download_and_restore" || "$MODE" == "schema_only" ]] && [ -z "$TARGET_DATE" ]; then
    log_error "--date is required for this mode."
    usage
fi

if [[ "$MODE" == "download_only" || "$MODE" == "download_and_restore" ]]; then
    if [ -z "$KEYSPACE_NAME" ]; then
        log_error "--keyspace must be specified for the --$MODE mode."
        usage
    fi
fi

# --- Cleanup & Trap Logic ---
TMP_KEY_FILE=$(mktemp)
chmod 600 "$TMP_KEY_FILE"

cleanup() {
    log_info "Running cleanup..."
    rm -f "$TMP_KEY_FILE"
    if [[ -n "$TEMP_RESTORE_DIR" && -d "$TEMP_RESTORE_DIR" ]]; then
        log_info "Removing temporary restore directory: $TEMP_RESTORE_DIR"
        rm -rf "$TEMP_RESTORE_DIR"
    fi
}
trap cleanup EXIT

# Extract key from config and write to temp file
ENCRYPTION_KEY=$(jq -r '.encryption_key' "$CONFIG_FILE")
if [ -z "$ENCRYPTION_KEY" ] || [ "$ENCRYPTION_KEY" == "null" ]; then
    log_error "encryption_key is empty or not found in $CONFIG_FILE"
    exit 1
fi
echo -n "$ENCRYPTION_KEY" > "$TMP_KEY_FILE"

# --- Define Effective Variables ---
EFFECTIVE_S3_BUCKET=${S3_BUCKET_OVERRIDE:-$S3_BUCKET_NAME}
EFFECTIVE_SOURCE_HOST=${SOURCE_HOST_OVERRIDE:-$HOSTNAME}


# --- Core Logic Functions ---

find_backup_chain() {
    log_info "Searching for backup chain to restore to point-in-time: $TARGET_DATE"
    
    local target_date_seconds
    local parsable_target_date="${TARGET_DATE:0:10} ${TARGET_DATE:11:2}:${TARGET_DATE:14:2}"
    target_date_seconds=$(date -d "$parsable_target_date" +%s 2>/dev/null)
    if [ -z "$target_date_seconds" ]; then
        log_error "Invalid date format for --date. Use 'YYYY-MM-DD-HH-MM'."
        exit 1
    fi

    log_info "Listing available backups from s3://$EFFECTIVE_S3_BUCKET/$EFFECTIVE_SOURCE_HOST/..."
    local all_backups
    all_backups=$(aws s3 ls "s3://$EFFECTIVE_S3_BUCKET/$EFFECTIVE_SOURCE_HOST/" | awk '{print $2}' | sed 's/\///' || echo "")

    if [ -z "$all_backups" ]; then
        log_error "No backups found for host '$EFFECTIVE_SOURCE_HOST' in bucket '$EFFECTIVE_S3_BUCKET'."
        log_error "Please check the bucket name and source host."
        exit 1
    fi

    local eligible_backups=()
    for backup_ts in $all_backups; do
        # Ensure backup_ts is in the correct format before parsing
        if [[ ! "$backup_ts" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{2}-[0-9]{2}$ ]]; then
            continue
        fi
        local parsable_backup_ts="${backup_ts:0:10} ${backup_ts:11:2}:${backup_ts:14:2}"
        local backup_date_seconds
        backup_date_seconds=$(date -d "$parsable_backup_ts" +%s 2>/dev/null || continue)
        if [[ -n "$backup_date_seconds" && "$backup_date_seconds" -le "$target_date_seconds" ]]; then
            eligible_backups+=("$backup_ts")
        fi
    done

    if [ ${#eligible_backups[@]} -eq 0 ]; then
        log_error "No backups found at or before the specified date."
        exit 1
    fi

    local sorted_backups
    sorted_backups=($(printf "%s\n" "${eligible_backups[@]}" | sort -r))

    CHAIN_TO_RESTORE=()
    BASE_FULL_BACKUP=""

    log_info "Analyzing backup manifests to build restore chain..."
    for backup_ts in "${sorted_backups[@]}"; do
        local manifest
        manifest=$(aws s3 cp "s3://$EFFECTIVE_S3_BUCKET/$EFFECTIVE_SOURCE_HOST/$backup_ts/backup_manifest.json" - 2>/dev/null || continue)
        
        if [ -z "$manifest" ]; then
            log_warn "Skipping backup '$backup_ts' as it has no manifest."
            continue
        fi

        CHAIN_TO_RESTORE+=("$backup_ts")
        local backup_type
        backup_type=$(echo "$manifest" | jq -r '.backup_type')
        
        if [ "$backup_type" == "full" ]; then
            BASE_FULL_BACKUP="$backup_ts"
            break
        fi
    done

    if [ -z "$BASE_FULL_BACKUP" ]; then
        log_error "Point-in-time recovery failed. Could not find a 'full' backup in the history for the specified date."
        exit 1
    fi

    CHAIN_TO_RESTORE=($(printf "%s\n" "${CHAIN_TO_RESTORE[@]}" | sort))
}

download_and_extract_table() {
    local archive_key="$1"
    local output_dir="$2"
    local temp_download_dir="$3"
    local check_path="$4"

    # Required variables for the subshell
    local EFFECTIVE_S3_BUCKET
    EFFECTIVE_S3_BUCKET=${S3_BUCKET_OVERRIDE:-$(jq -r '.s3_bucket_name' "$CONFIG_FILE")}

    # Safety check before downloading this table's data
    log_info "Checking disk usage on $check_path before downloading..."
    if ! /usr/local/bin/disk-health-check.sh -p "$check_path" -w 90 -c 95; then
        log_error "Disk usage is high. Aborting download for archive $archive_key."
        return 1
    fi

    mkdir -p "$output_dir"
    
    log_info "Downloading data for $archive_key to $output_dir"
    
    local pid=$$
    local tid=$(date +%s%N)
    local temp_enc_file="$temp_download_dir/temp_${pid}_${tid}.tar.gz.enc"
    local temp_tar_file="$temp_download_dir/temp_${pid}_${tid}.tar.gz"

    if ! nice -n 19 ionice -c 3 aws s3 cp --quiet "s3://$EFFECTIVE_S3_BUCKET/$archive_key" "$temp_enc_file"; then
        log_error "Failed to download $archive_key."
        rm -f "$temp_enc_file" # Clean up partial download
        return 1
    fi

    if ! nice -n 19 ionice -c 3 openssl enc -d -aes-256-cbc -salt -pbkdf2 -md sha256 -in "$temp_enc_file" -out "$temp_tar_file" -pass "file:$TMP_KEY_FILE"; then
        log_error "Failed to decrypt $archive_key. Check encryption key and file integrity."
        rm -f "$temp_enc_file" "$temp_tar_file"
        return 1
    fi

    if ! nice -n 19 ionice -c 3 tar -xzf "$temp_tar_file" -C "$output_dir"; then
        log_error "Failed to extract $archive_key. Archive is likely corrupt."
        rm -f "$temp_enc_file" "$temp_tar_file"
        return 1
    fi
    
    rm -f "$temp_enc_file" "$temp_tar_file"
    return 0
}

do_full_restore() {
    log_info "--- Starting FULL DESTRUCTIVE Node Restore ---"
    log_warn "This will restore the node by wiping all data and replacing it directly from the backup files."
    log_warn "WARNING: This is a DESTRUCTIVE operation. It will:"
    log_warn "1. STOP the Cassandra service."
    log_warn "2. WIPE ALL DATA AND COMMITLOGS from $CASSANDRA_DATA_DIR and $CASSANDRA_COMMITLOG_DIR."
    log_warn "3. DOWNLOAD all backup data to a temporary location."
    log_warn "4. CONFIGURE cassandra.yaml with the node's original tokens."
    log_warn "5. MOVE the restored data into the final Cassandra data directory."
    log_warn "6. START Cassandra and verify it rejoins the cluster."
    
    if [ "$AUTO_APPROVE" = false ]; then
        read -p "Are you absolutely sure you want to PERMANENTLY DELETE ALL DATA on this node? Type 'yes': " confirmation
        if [[ "$confirmation" != "yes" ]]; then
            log_info "Restore aborted by user."
            exit 0
        fi
    else
        log_warn "Auto-approving destructive full restore via --yes flag."
    fi

    # === PHASE 1: PREPARATION (OFFLINE) ===
    log_info "--- PHASE 1: PREPARATION ---"

    log_info "1. Stopping Cassandra service..."
    if systemctl is-active --quiet cassandra; then
      systemctl stop cassandra
    else
      log_info "Cassandra service is already stopped."
    fi

    log_info "2. Wiping old data directories..."
    rm -rf "$CASSANDRA_DATA_DIR"
    mkdir -p "$CASSANDRA_DATA_DIR"
    rm -rf "$CASSANDRA_COMMITLOG_DIR"
    mkdir -p "$CASSANDRA_COMMITLOG_DIR"
    rm -rf "$CASSANDRA_CACHES_DIR"
    mkdir -p "$CASSANDRA_CACHES_DIR"
    log_success "Old directories wiped and recreated."
    
    TEMP_RESTORE_DIR="${RESTORE_BASE_PATH}/restore_temp_$$"
    log_info "3. Creating temporary restore directory: $TEMP_RESTORE_DIR"
    mkdir -p "$TEMP_RESTORE_DIR"

    # === PHASE 2: CONFIGURATION & DATA DOWNLOAD (OFFLINE) ===
    log_info "--- PHASE 2: CONFIGURATION & DATA DOWNLOAD ---"
    
    log_info "4. Downloading manifest from base full backup to extract tokens..."
    local base_manifest
    base_manifest=$(aws s3 cp "s3://$EFFECTIVE_S3_BUCKET/$EFFECTIVE_SOURCE_HOST/$BASE_FULL_BACKUP/backup_manifest.json" - 2>/dev/null)
    if [ -z "$base_manifest" ]; then
        log_error "Cannot download manifest for base backup $BASE_FULL_BACKUP. Aborting."
        exit 1
    fi
    
    local tokens_csv
    tokens_csv=$(echo "$base_manifest" | jq -r '.source_node.tokens | join(",")')
    local token_count
    token_count=$(echo "$base_manifest" | jq -r '.source_node.tokens | length')

    if [ -z "$tokens_csv" ] || [ "$token_count" -le 0 ]; then
        log_error "No tokens found in the backup manifest. Cannot restore node identity."
        exit 1
    fi
    
    log_info "5. Applying original tokens to cassandra.yaml..."
    local cassandra_yaml="$CASSANDRA_CONF_DIR/cassandra.yaml"
    
    sed -i '/^initial_token:/d' "$cassandra_yaml"
    sed -i '/^num_tokens:/d' "$cassandra_yaml"
    
    echo "num_tokens: $token_count" >> "$cassandra_yaml"
    echo "initial_token: $tokens_csv" >> "$cassandra_yaml"
    log_success "Successfully configured node with $token_count tokens."

    log_info "6. Downloading and extracting all data from backup chain in parallel..."
    local SCHEMA_MAP_JSON
    SCHEMA_MAP_JSON=$(aws s3 cp "s3://$EFFECTIVE_S3_BUCKET/$EFFECTIVE_SOURCE_HOST/$BASE_FULL_BACKUP/schema_mapping.json" - 2>/dev/null)
    if [ -z "$SCHEMA_MAP_JSON" ]; then
        log_error "Cannot download schema_mapping.json for base backup $BASE_FULL_BACKUP. Aborting."
        exit 1
    fi
    log_info "Schema-to-directory mapping downloaded."
    
    export -f download_and_extract_table log_message log_info log_error
    export RESTORE_LOG_FILE CONFIG_FILE S3_BUCKET_OVERRIDE TMP_KEY_FILE TEMP_RESTORE_DIR RESTORE_BASE_PATH
    export RED GREEN YELLOW BLUE NC

    for backup_ts in "${CHAIN_TO_RESTORE[@]}"; do
        log_info "Processing backup: $backup_ts"
        aws s3 ls --recursive "s3://$EFFECTIVE_S3_BUCKET/$EFFECTIVE_SOURCE_HOST/$backup_ts/" | grep '\.tar\.gz\.enc$' | awk '{print $4}' | \
        xargs -I{} -P"$PARALLELISM" bash -c '
            archive_key="$1"
            effective_source_host="$2"
            current_backup_ts="$3"
            schema_map_json=$(cat)

            s3_path_no_host=$(echo "$archive_key" | sed "s#$effective_source_host/$current_backup_ts/##")
            ks_dir=$(echo "$s3_path_no_host" | cut -d"/" -f1)
            table_dir_name=$(echo "$s3_path_no_host" | cut -d"/" -f2)
            table_name=$(echo "$table_dir_name" | rev | cut -d"-" -f2- | rev)

            table_uuid_dir=$(echo "$schema_map_json" | jq -r ".\"${ks_dir}.${table_name}\"")
            if [ -z "$table_uuid_dir" ] || [ "$table_uuid_dir" == "null" ]; then
                log_message "${YELLOW}WARNING: Could not find mapping for ${ks_dir}.${table_name}. Skipping archive $archive_key${NC}"
                exit 0
            fi
            
            output_dir="$TEMP_RESTORE_DIR/$ks_dir/$table_uuid_dir"
            download_and_extract_table "$archive_key" "$output_dir" "$TEMP_RESTORE_DIR" "$RESTORE_BASE_PATH"
        ' _ "{}" "$EFFECTIVE_SOURCE_HOST" "$backup_ts" <<< "$SCHEMA_MAP_JSON"
    done
    log_success "All data from backup chain downloaded and extracted to temporary directory."

    # === PHASE 3: DATA PLACEMENT AND STARTUP ===
    log_info "--- PHASE 3: FINALIZATION ---"

    log_info "7. Moving restored data from temporary dir to final data directory..."
    rsync -a "$TEMP_RESTORE_DIR/" "$CASSANDRA_DATA_DIR/"
    log_success "Data moved successfully."
    
    log_info "8. Setting correct ownership for all Cassandra directories..."
    chown -R "$CASSANDRA_USER":"$CASSANDRA_USER" "$CASSANDRA_DATA_DIR"
    chown -R "$CASSANDRA_USER":"$CASSANDRA_USER" "$CASSANDRA_COMMITLOG_DIR"
    chown -R "$CASSANDRA_USER":"$CASSANDRA_USER" "$CASSANDRA_CACHES_DIR"

    log_info "9. Starting Cassandra service..."
    systemctl start cassandra
    
    log_info "Waiting for Cassandra to initialize and come online..."
    local CASSANDRA_READY=false
    for i in {1..60}; do # Wait up to 10 minutes
        if nodetool status 2>/dev/null | grep "$LISTEN_ADDRESS" | grep -q 'UN'; then
            CASSANDRA_READY=true
            break
        fi
        log_info "Waiting for node to report UP/NORMAL... (attempt $i of 60)"
        sleep 10
    done

    if [ "$CASSANDRA_READY" = false ]; then
        log_error "Cassandra did not become ready. Check system logs."
        exit 1
    fi
    
    log_success "Cassandra is online and ready."
    log_info "10. Restore complete. The temporary directory $TEMP_RESTORE_DIR will now be removed."
    
    log_success "--- Full Restore Process Finished Successfully ---"
}

do_granular_restore() {
    log_info "--- Starting GRANULAR Restore for $KEYSPACE_NAME${TABLE_NAME:+.${TABLE_NAME}} ---"

    local base_output_dir
    local temp_download_dir
    local check_path

    if [ "$MODE" == "download_only" ]; then
        base_output_dir="$DOWNLOAD_ONLY_PATH"
        temp_download_dir="$DOWNLOAD_ONLY_PATH"
        check_path="$DOWNLOAD_ONLY_PATH"
        log_info "Action: Download-Only. Data will be saved to $base_output_dir"
        mkdir -p "$base_output_dir"
    else
        TEMP_RESTORE_DIR="${RESTORE_BASE_PATH}/restore_temp_$$"
        base_output_dir="$TEMP_RESTORE_DIR"
        temp_download_dir="$TEMP_RESTORE_DIR"
        check_path="$RESTORE_BASE_PATH"
        log_info "Action: Download & Restore. Using temporary directory $base_output_dir"
        mkdir -p "$base_output_dir"
    fi
    
    log_info "Performing pre-flight disk usage check on $check_path..."
    if ! /usr/local/bin/disk-health-check.sh -p "$check_path" -w 80 -c 90; then
        log_error "Insufficient disk space on the target volume. Aborting granular restore."
        exit 1
    fi
    log_success "Disk usage is sufficient to begin."

    local SCHEMA_MAP_JSON
    SCHEMA_MAP_JSON=$(aws s3 cp "s3://$EFFECTIVE_S3_BUCKET/$EFFECTIVE_SOURCE_HOST/$BASE_FULL_BACKUP/schema_mapping.json" - 2>/dev/null)
    if [ -z "$SCHEMA_MAP_JSON" ]; then
        log_error "Cannot download schema_mapping.json for base backup $BASE_FULL_BACKUP. Aborting."
        exit 1
    fi
    log_info "Schema-to-directory mapping downloaded."

    export -f download_and_extract_table log_message log_info log_error
    export RESTORE_LOG_FILE CONFIG_FILE S3_BUCKET_OVERRIDE TMP_KEY_FILE EFFECTIVE_SOURCE_HOST KEYSPACE_NAME TABLE_NAME base_output_dir temp_download_dir check_path
    export RED GREEN YELLOW BLUE NC

    for backup_ts in "${CHAIN_TO_RESTORE[@]}"; do
        log_info "Processing backup: $backup_ts"
        aws s3 ls --recursive "s3://$EFFECTIVE_S3_BUCKET/$EFFECTIVE_SOURCE_HOST/$backup_ts/$KEYSPACE_NAME/" | grep '\.tar\.gz\.enc$' | awk '{print $4}' | while read -r archive_key; do
            if [ -n "$TABLE_NAME" ] && [[ ! "$archive_key" =~ "/${TABLE_NAME}/" ]]; then
                continue
            fi
            echo "$archive_key"
        done | xargs -I{} -P"$PARALLELISM" bash -c '
            archive_key="$1"
            effective_source_host="$2"
            current_backup_ts="$3"
            schema_map_json=$(cat)

            s3_path_no_host=$(echo "$archive_key" | sed "s#$effective_source_host/$current_backup_ts/##")
            ks_dir=$(echo "$s3_path_no_host" | cut -d"/" -f1)
            table_dir_name=$(echo "$s3_path_no_host" | cut -d"/" -f2)
            table_name=$(echo "$table_dir_name" | rev | cut -d"-" -f2- | rev)

            table_uuid_dir=$(echo "$schema_map_json" | jq -r ".\"${ks_dir}.${table_name}\"")
            if [ -z "$table_uuid_dir" ] || [ "$table_uuid_dir" == "null" ]; then
                log_message "${YELLOW}WARNING: Could not find mapping for ${ks_dir}.${table_name}. Skipping archive $archive_key${NC}"
                exit 0
            fi
            
            output_dir="$base_output_dir/$ks_dir/$table_uuid_dir"
            download_and_extract_table "$archive_key" "$output_dir" "$temp_download_dir" "$check_path"
        ' _ "{}" "$EFFECTIVE_SOURCE_HOST" "$backup_ts" <<< "$SCHEMA_MAP_JSON"
    done
    
    if [ "$MODE" == "download_only" ]; then
        log_success "--- Granular Restore (Download Only) Finished Successfully ---"
        log_info "All data has been downloaded and decrypted to: $base_output_dir"
    else
        log_info "All data has been downloaded. Preparing to load into cluster."
        
        load_table_data() {
            local source_table_dir="$1"
            local downloaded_table_name_with_uuid
            downloaded_table_name_with_uuid=$(basename "$source_table_dir")
            local downloaded_table_name
            downloaded_table_name=$(echo "$downloaded_table_name_with_uuid" | rev | cut -d'-' -f2- | rev)

            log_info "Processing table for restore: $KEYSPACE_NAME.$downloaded_table_name"

            local live_table_dir
            live_table_dir=$(find "$CASSANDRA_DATA_DIR/$KEYSPACE_NAME" -maxdepth 1 -type d -name "$downloaded_table_name-*" 2>/dev/null | head -n 1)
            
            if [ -z "$live_table_dir" ]; then
                log_error "Cannot find live table directory for '$KEYSPACE_NAME.$downloaded_table_name'. Skipping restore."
                return 1
            fi

            local live_table_dirname
            live_table_dirname=$(basename "$live_table_dir")
            local final_table_dir_path
            final_table_dir_path="$(dirname "$source_table_dir")/$live_table_dirname"

            if [ "$downloaded_table_name_with_uuid" != "$live_table_dirname" ]; then
                log_info "Renaming downloaded directory for '$downloaded_table_name' to match live cluster UUID."
                mv "$source_table_dir" "$final_table_dir_path"
            fi
            
            chown -R "$CASSANDRA_USER":"$CASSANDRA_USER" "$final_table_dir_path"

            export CASSANDRA_CONF="$CASSANDRA_CONF_DIR"
            local loader_cmd=("sstableloader" "--verbose" "--no-progress" "-d" "$LOADER_NODES")
            
            if [[ "$CASSANDRA_PASSWORD" != "null" ]]; then
                loader_cmd+=("-u" "$CASSANDRA_USER" "-pw" "$CASSANDRA_PASSWORD")
            fi
            if [ "$SSL_ENABLED" == "true" ]; then
                loader_cmd+=("--ssl-storage-port" "7001")
            fi
            loader_cmd+=("$final_table_dir_path")

            log_info "Executing sstableloader for $KEYSPACE_NAME.$downloaded_table_name"
            if ! "${loader_cmd[@]}"; then
                log_error "sstableloader failed for table $KEYSPACE_NAME.$downloaded_table_name."
            else
                 log_success "Successfully loaded data for table $KEYSPACE_NAME.$downloaded_table_name."
                 rm -rf "$final_table_dir_path"
            fi
        }
        export -f load_table_data log_message log_info log_error
        export RESTORE_LOG_FILE CASSANDRA_DATA_DIR KEYSPACE_NAME CASSANDRA_USER CASSANDRA_CONF_DIR LOADER_NODES CASSANDRA_PASSWORD SSL_ENABLED
        export RED GREEN YELLOW BLUE NC
        
        find "$base_output_dir/$KEYSPACE_NAME" -maxdepth 1 -mindepth 1 -type d | xargs -I{} -P"$PARALLELISM" bash -c 'load_table_data "{}"'

        log_success "--- Granular Restore (Download & Restore) Finished ---"
    fi
}

do_schema_only_restore() {
    log_info "--- Starting Schema-Only Restore ---"

    if [ -z "$BASE_FULL_BACKUP" ]; then
        log_error "Cannot proceed without a base full backup in the chain."
        exit 1
    fi

    log_info "Base full backup selected for schema extraction: $BASE_FULL_BACKUP"

    local schema_s3_path="s3://$EFFECTIVE_S3_BUCKET/$EFFECTIVE_SOURCE_HOST/$BASE_FULL_BACKUP/schema.cql"
    local local_schema_path="/tmp/schema_restore.cql"

    log_info "Downloading schema from: $schema_s3_path"
    if ! aws s3 cp --quiet "$schema_s3_path" "$local_schema_path"; then
        log_error "Failed to download schema.cql."
        exit 1
    fi

    log_success "--- Schema Restore Finished Successfully ---"
    log_info "The schema has been downloaded to: $local_schema_path"
    log_message ""
    log_info "NEXT STEPS:"
    log_info "1. Manually review the schema file: less $local_schema_path"
    log_info "2. On ONE node in your new cluster, apply the schema using cqlsh:"
    
    local cqlsh_creds=""
    if [[ "$CASSANDRA_PASSWORD" != "null" ]]; then
        cqlsh_creds="-u $CASSANDRA_USER -p 'YourPassword'"
    fi
    local cqlsh_ssl=""
    if [[ "$SSL_ENABLED" == "true" ]]; then
        cqlsh_ssl="--ssl"
    fi
    log_info "   cqlsh $cqlsh_creds $cqlsh_ssl -f $local_schema_path"
    log_info "3. Once the schema is applied, you can proceed with the data restore."
}

do_list_backups() {
    log_info "--- Listing Available Backups for Host: $EFFECTIVE_SOURCE_HOST ---"
    
    local all_backups
    all_backups=$(aws s3 ls "s3://$EFFECTIVE_S3_BUCKET/$EFFECTIVE_SOURCE_HOST/" | awk '{print $2}' | sed 's/\///' || echo "")

    if [ -z "$all_backups" ]; then
        log_warn "No backups found for host '$EFFECTIVE_SOURCE_HOST' in bucket '$EFFECTIVE_S3_BUCKET'."
        return 0
    fi
    
    printf "\n"
    printf "%b\n" "${BOLD}${GREEN}Host: ${EFFECTIVE_SOURCE_HOST}${NC}"
    printf "%b\n" "${YELLOW}----------------------------${NC}"

    local backups_to_sort=()
    while IFS= read -r backup_ts; do
        if [[ ! "$backup_ts" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{2}-[0-9]{2}$ ]]; then
            continue
        fi

        manifest=$(aws s3 cp "s3://$EFFECTIVE_S3_BUCKET/$EFFECTIVE_SOURCE_HOST/$backup_ts/backup_manifest.json" - 2>/dev/null || echo "{}")
        backup_type=$(echo "$manifest" | jq -r '.backup_type // "unknown"')
        
        local type_color=$NC
        if [ "$backup_type" == "full" ]; then
            type_color=${CYAN}
        elif [ "$backup_type" == "incremental" ]; then
            type_color=${BLUE}
        fi
        
        local formatted_line="  - ${BOLD}${backup_ts}${NC} (type: ${type_color}${backup_type}${NC})"
        backups_to_sort+=("$(printf "${backup_ts}\t${formatted_line}")")

    done <<< "$all_backups"

    if [ ${#backups_to_sort[@]} -eq 0 ]; then
        log_warn "No valid backup sets found to list."
        return
    fi
    
    printf "%s\n" "${backups_to_sort[@]}" | sort | cut -d$'\t' -f2- | while IFS= read -r line; do
        printf "%b\n" "$line"
    done

    printf "\n"
}

do_show_restore_chain() {
    log_info "--- Showing Restore Chain for Target Date: $TARGET_DATE ---"
    
    find_backup_chain

    if [ ${#CHAIN_TO_RESTORE[@]} -eq 0 ]; then
        log_warn "No valid restore chain could be built for the specified date."
        return 1
    fi

    printf "\n"
    printf "%b\n" "${BOLD}${GREEN}Restore chain for host '${EFFECTIVE_SOURCE_HOST}' to point-in-time '${TARGET_DATE}':${NC}"
    printf "%b\n" "${YELLOW}------------------------------------------------------------------${NC}"

    for backup_ts in "${CHAIN_TO_RESTORE[@]}"; do
        if [ "$backup_ts" == "$BASE_FULL_BACKUP" ]; then
            printf "%b\n" "  - ${BOLD}${backup_ts}${NC} (${CYAN}Full Backup - Base${NC})"
        else
            printf "%b\n" "  - ${BOLD}${backup_ts}${NC} (${BLUE}Incremental${NC})"
        fi
    done
    printf "%b\n" "${YELLOW}------------------------------------------------------------------${NC}"
    printf "\n"
}


# --- Main Execution ---

log_info "--- Starting Point-in-Time Restore Manager ---"
log_info "Target S3 Bucket: $EFFECTIVE_S3_BUCKET"
log_info "Source Hostname for Restore: $EFFECTIVE_SOURCE_HOST"
log_info "Parallelism: $PARALLELISM"

if [ "$BACKUP_BACKEND" != "s3" ]; then
    log_error "This restore script only supports the 's3' backup backend."
    exit 1
fi

case $MODE in
    "list")
        do_list_backups
        exit 0
        ;;
    "chain")
        do_show_restore_chain
        exit 0
        ;;
esac


find_backup_chain

log_info "Backup chain to be restored (chronological order):"
printf " - %s\n" "${CHAIN_TO_RESTORE[@]}"
log_info "Base full backup for this chain is: $BASE_FULL_BACKUP"

if [ "$AUTO_APPROVE" = false ]; then
    read -p "Does the restore chain above look correct? Type 'yes' to proceed: " manifest_confirmation
    if [[ "$manifest_confirmation" != "yes" ]]; then
        log_info "Restore aborted by user based on chain review."
        exit 0
    fi
else
    log_warn "Auto-approving restore chain via --yes flag."
fi

case $MODE in
    "full")
        do_full_restore
        ;;
    "download_only")
        do_granular_restore
        ;;
    "download_and_restore")
        do_granular_restore
        ;;
    "schema_only")
        do_schema_only_restore
        ;;
    *)
        log_error "INTERNAL ERROR: Invalid mode detected for execution: $MODE"
        usage
        exit 1
        ;;
esac

exit 0
