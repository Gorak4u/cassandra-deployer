
#!/bin/bash
# Restores a Cassandra node from backups in S3 to a specific point in time.
# This script can combine a full backup with subsequent incremental backups.
# Supports full node restore, granular keyspace/table restore.

set -euo pipefail

# --- Configuration & Input ---
CONFIG_FILE="/etc/backup/config.json"
# Define a default log file path in case config loading fails, ensuring early errors are logged.
RESTORE_LOG_FILE="/var/log/cassandra/restore.log"

log_message() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$RESTORE_LOG_FILE"
}

# --- Pre-flight Checks ---
# Run these checks as early as possible so any failure is logged.
if [ "$(id -u)" -ne 0 ]; then
    log_message "ERROR: This script must be run as root."
    exit 1
fi

for tool in jq aws sstableloader openssl pgrep ps cqlsh rsync /usr/local/bin/disk-health-check.sh; do
    if ! command -v $tool &>/dev/null; then
        log_message "ERROR: Required tool '$tool' is not installed or not in PATH."
        exit 1
    fi
done

if [ ! -f "$CONFIG_FILE" ]; then
    log_message "ERROR: Backup configuration file not found at $CONFIG_FILE"
    exit 1
fi

# --- Variables defined after initial checks ---
HOSTNAME=$(hostname -s)
TEMP_RESTORE_DIR="" # Global variable to track the temporary directory

# --- Usage ---
usage() {
    log_message "Usage: $0 --date <timestamp> [options]"
    log_message ""
    log_message "Required:"
    log_message "  --date <timestamp>                   Target UTC timestamp for recovery in 'YYYY-MM-DD-HH-MM' format."
    log_message ""
    log_message "Modes (choose one):"
    log_message "  --full-restore                       Performs a full, destructive restore of the entire node."
    log_message "  --keyspace <ks> [--table <table>]    Targets a specific keyspace or table for a granular restore (requires an action)."
    log_message ""
    log_message "Actions for Granular Restore (required if --keyspace is used):"
    log_message "  --download-only                      Download and decrypt data to a derived path inside /var/lib/cassandra."
    log_message "  --download-and-restore             Download data and load it into the cluster via sstableloader."
    log_message ""
    log_message "Restore Source Options (optional):"
    log_message "  --s3-bucket <name>                   Override the S3 bucket from config.json."
    log_message "  --source-host <hostname>             Restore from a backup of a different host. Defaults to the current hostname."
    log_message ""
    log_message "Automation:"
    log_message "  --yes                                Skips all interactive confirmation prompts. Use with caution."
    exit 1
}


# --- Source configuration from JSON ---
S3_BUCKET_NAME=$(jq -r '.s3_bucket_name' "$CONFIG_FILE")
CASSANDRA_DATA_DIR=$(jq -r '.cassandra_data_dir' "$CONFIG_FILE")
CASSANDRA_CONF_DIR=$(jq -r '.config_dir_path' "$CONFIG_FILE")
CASSANDRA_COMMITLOG_DIR=$(jq -r '.commitlog_dir' "$CONFIG_FILE")
CASSANDRA_CACHES_DIR=$(jq -r '.saved_caches_dir' "$CONFIG_FILE")
LISTEN_ADDRESS=$(jq -r '.listen_address' "$CONFIG_FILE")
SEEDS=$(jq -r '.seeds_list | join(",")' "$CONFIG_FILE")
CASSANDRA_USER=$(jq -r '.cassandra_user // "cassandra"' "$CONFIG_FILE")
CASSANDRA_PASSWORD=$(jq -r '.cassandra_password' "$CONFIG_FILE")
SSL_ENABLED=$(jq -r '.ssl_enabled // "false"' "$CONFIG_FILE")
BACKUP_BACKEND=$(jq -r '.backup_backend // "s3"' "$CONFIG_FILE")

# Validate essential configuration
if [ -z "$CASSANDRA_CONF_DIR" ] || [ "$CASSANDRA_CONF_DIR" == "null" ] || [ ! -d "$CASSANDRA_CONF_DIR" ]; then log_message "ERROR: 'config_dir_path' is not set or invalid in $CONFIG_FILE."; exit 1; fi
if [ -z "$CASSANDRA_DATA_DIR" ] || [ "$CASSANDRA_DATA_DIR" == "null" ]; then log_message "ERROR: 'cassandra_data_dir' is not set in $CONFIG_FILE."; exit 1; fi
if [ -z "$CASSANDRA_COMMITLOG_DIR" ] || [ "$CASSANDRA_COMMITLOG_DIR" == "null" ]; then log_message "ERROR: 'commitlog_dir' is not set in $CONFIG_FILE."; exit 1; fi
if [ -z "$CASSANDRA_CACHES_DIR" ] || [ "$CASSANDRA_CACHES_DIR" == "null" ]; then log_message "ERROR: 'saved_caches_dir' is not set in $CONFIG_FILE."; exit 1; fi
if [ -z "$LISTEN_ADDRESS" ] || [ "$LISTEN_ADDRESS" == "null" ]; then log_message "ERROR: 'listen_address' is not set in $CONFIG_FILE."; exit 1; fi


# Derive restore paths from the main data directory parameter
RESTORE_BASE_PATH="${CASSANDRA_DATA_DIR%/*}" # e.g., /var/lib/cassandra
DOWNLOAD_ONLY_PATH="${RESTORE_BASE_PATH}/restore_download"


# Determine node list for sstableloader. Use seeds if available, otherwise localhost.
if [ -n "$SEEDS" ]; then
    LOADER_NODES="$SEEDS"
else
    LOADER_NODES="$LISTEN_ADDRESS"
fi

# --- Argument Parsing (to be parsed) ---
TARGET_DATE=""
KEYSPACE_NAME=""
TABLE_NAME=""
MODE="" # Will be set to 'granular' or 'full'
RESTORE_ACTION="" # For granular: 'download_only' or 'download_and_restore'
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
        --download-only) RESTORE_ACTION="download_only" ;;
        --download-and-restore) RESTORE_ACTION="download_and_restore" ;;
        --yes) AUTO_APPROVE=true ;;
        *) log_message "Unknown parameter passed: $1"; usage ;;
    esac
    shift
done

# Validate arguments
if [ -z "$TARGET_DATE" ]; then
    log_message "ERROR: --date is a required argument."
    usage
fi

if [ -n "$KEYSPACE_NAME" ] && [ -z "$MODE" ]; then
    MODE="granular"
fi

if [ "$MODE" = "granular" ]; then
    if [ -z "$KEYSPACE_NAME" ]; then
        log_message "ERROR: --keyspace must be specified for a granular restore."
        usage
    fi
    if [ -z "$RESTORE_ACTION" ]; then
        log_message "ERROR: You must specify an action (--download-only or --download-and-restore) for a granular restore."
        usage
    fi
fi

# --- Cleanup & Trap Logic ---
TMP_KEY_FILE=$(mktemp)
chmod 600 "$TMP_KEY_FILE"

cleanup() {
    log_message "Running cleanup..."
    rm -f "$TMP_KEY_FILE"
    if [[ -n "$TEMP_RESTORE_DIR" && -d "$TEMP_RESTORE_DIR" ]]; then
        log_message "Removing temporary restore directory: $TEMP_RESTORE_DIR"
        rm -rf "$TEMP_RESTORE_DIR"
    fi
}
trap cleanup EXIT

# Extract key from config and write to temp file
ENCRYPTION_KEY=$(jq -r '.encryption_key' "$CONFIG_FILE")
if [ -z "$ENCRYPTION_KEY" ] || [ "$ENCRYPTION_KEY" == "null" ]; then
    log_message "ERROR: encryption_key is empty or not found in $CONFIG_FILE"
    exit 1
fi
echo -n "$ENCRYPTION_KEY" > "$TMP_KEY_FILE"

# --- Define Effective Variables ---
EFFECTIVE_S3_BUCKET=${S3_BUCKET_OVERRIDE:-$S3_BUCKET_NAME}
EFFECTIVE_SOURCE_HOST=${SOURCE_HOST_OVERRIDE:-$HOSTNAME}


# --- Core Logic Functions ---

find_backup_chain() {
    log_message "Searching for backup chain to restore to point-in-time: $TARGET_DATE"
    
    local target_date_seconds
    local parsable_target_date="${TARGET_DATE:0:10} ${TARGET_DATE:11:2}:${TARGET_DATE:14:2}"
    target_date_seconds=$(date -d "$parsable_target_date" +%s 2>/dev/null)
    if [ -z "$target_date_seconds" ]; then
        log_message "ERROR: Invalid date format for --date. Use 'YYYY-MM-DD-HH-MM'."
        exit 1
    fi

    log_message "Listing available backups from s3://$EFFECTIVE_S3_BUCKET/$EFFECTIVE_SOURCE_HOST/..."
    local all_backups
    all_backups=$(aws s3 ls "s3://$EFFECTIVE_S3_BUCKET/$EFFECTIVE_SOURCE_HOST/" | awk '{print $2}' | sed 's/\///' || echo "")

    if [ -z "$all_backups" ]; then
        log_message "ERROR: No backups found for host '$EFFECTIVE_SOURCE_HOST' in bucket '$EFFECTIVE_S3_BUCKET'."
        log_message "Please check the bucket name and source host."
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
        log_message "ERROR: No backups found at or before the specified date."
        exit 1
    fi

    local sorted_backups
    sorted_backups=($(printf "%s\n" "${eligible_backups[@]}" | sort -r))

    CHAIN_TO_RESTORE=()
    BASE_FULL_BACKUP=""

    log_message "Analyzing backup manifests to build restore chain..."
    for backup_ts in "${sorted_backups[@]}"; do
        local manifest
        manifest=$(aws s3 cp "s3://$EFFECTIVE_S3_BUCKET/$EFFECTIVE_SOURCE_HOST/$backup_ts/backup_manifest.json" - 2>/dev/null || continue)
        
        if [ -z "$manifest" ]; then
            log_message "WARNING: Skipping backup '$backup_ts' as it has no manifest."
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
        log_message "ERROR: Point-in-time recovery failed. Could not find a 'full' backup in the history for the specified date."
        exit 1
    fi

    CHAIN_TO_RESTORE=($(printf "%s\n" "${CHAIN_TO_RESTORE[@]}" | sort))
}


do_full_restore() {
    log_message "--- Starting SIMPLIFIED FULL DESTRUCTIVE Node Restore ---"
    log_message "This will restore the node by wiping all data and replacing it directly from the backup files."
    log_message "WARNING: This is a DESTRUCTIVE operation. It will:"
    log_message "1. STOP the Cassandra service."
    log_message "2. WIPE ALL DATA AND COMMITLOGS from $CASSANDRA_DATA_DIR and $CASSANDRA_COMMITLOG_DIR."
    log_message "3. DOWNLOAD all backup data to a temporary location."
    log_message "4. CONFIGURE cassandra.yaml with the node's original tokens."
    log_message "5. MOVE the restored data into the final Cassandra data directory."
    log_message "6. START Cassandra."
    
    if [ "$AUTO_APPROVE" = false ]; then
        read -p "Are you absolutely sure you want to PERMANENTLY DELETE ALL DATA on this node? Type 'yes': " confirmation
        if [[ "$confirmation" != "yes" ]]; then
            log_message "Restore aborted by user."
            exit 0
        fi
    else
        log_message "Auto-approving destructive full restore via --yes flag."
    fi

    # === PHASE 1: PREPARATION (OFFLINE) ===
    log_message "--- PHASE 1: PREPARATION ---"

    log_message "1. Stopping Cassandra service..."
    if systemctl is-active --quiet cassandra; then
      systemctl stop cassandra
    else
      log_message "Cassandra service is already stopped."
    fi

    log_message "2. Wiping old data directories..."
    rm -rf "$CASSANDRA_DATA_DIR"
    mkdir -p "$CASSANDRA_DATA_DIR"
    rm -rf "$CASSANDRA_COMMITLOG_DIR"
    mkdir -p "$CASSANDRA_COMMITLOG_DIR"
    rm -rf "$CASSANDRA_CACHES_DIR"
    mkdir -p "$CASSANDRA_CACHES_DIR"
    log_message "Old directories wiped and recreated."
    
    TEMP_RESTORE_DIR="${RESTORE_BASE_PATH}/restore_temp_$$"
    log_message "3. Creating temporary restore directory: $TEMP_RESTORE_DIR"
    mkdir -p "$TEMP_RESTORE_DIR"

    # === PHASE 2: CONFIGURATION & DATA DOWNLOAD (OFFLINE) ===
    log_message "--- PHASE 2: CONFIGURATION & DATA DOWNLOAD ---"
    
    log_message "4. Downloading manifest from base full backup to extract tokens..."
    local base_manifest
    base_manifest=$(aws s3 cp "s3://$EFFECTIVE_S3_BUCKET/$EFFECTIVE_SOURCE_HOST/$BASE_FULL_BACKUP/backup_manifest.json" - 2>/dev/null)
    if [ -z "$base_manifest" ]; then
        log_message "ERROR: Cannot download manifest for base backup $BASE_FULL_BACKUP. Aborting."
        exit 1
    fi
    
    local tokens_csv
    tokens_csv=$(echo "$base_manifest" | jq -r '.source_node.tokens | join(",")')
    local token_count
    token_count=$(echo "$base_manifest" | jq -r '.source_node.tokens | length')

    if [ -z "$tokens_csv" ] || [ "$token_count" -le 0 ]; then
        log_message "ERROR: No tokens found in the backup manifest. Cannot restore node identity."
        exit 1
    fi
    
    log_message "5. Applying original tokens to cassandra.yaml..."
    local cassandra_yaml="$CASSANDRA_CONF_DIR/cassandra.yaml"
    
    # Remove existing lines to prevent duplicates
    sed -i '/^initial_token:/d' "$cassandra_yaml"
    sed -i '/^num_tokens:/d' "$cassandra_yaml"
    
    # Append the restored token configuration
    echo "num_tokens: $token_count" >> "$cassandra_yaml"
    echo "initial_token: $tokens_csv" >> "$cassandra_yaml"
    log_message "Successfully configured node with $token_count tokens."

    log_message "6. Downloading and extracting all data from backup chain..."
    # Download the schema mapping first
    local SCHEMA_MAP_JSON
    SCHEMA_MAP_JSON=$(aws s3 cp "s3://$EFFECTIVE_S3_BUCKET/$EFFECTIVE_SOURCE_HOST/$BASE_FULL_BACKUP/schema_mapping.json" - 2>/dev/null)
    if [ -z "$SCHEMA_MAP_JSON" ]; then
        log_message "ERROR: Cannot download schema_mapping.json for base backup $BASE_FULL_BACKUP. Aborting."
        exit 1
    fi
    log_message "Schema-to-directory mapping downloaded."

    for backup_ts in "${CHAIN_TO_RESTORE[@]}"; do
        log_message "Processing backup: $backup_ts"
        # List all S3 objects ending in .tar.gz.enc for the current backup timestamp
        aws s3 ls --recursive "s3://$EFFECTIVE_S3_BUCKET/$EFFECTIVE_SOURCE_HOST/$backup_ts/" | grep '\.tar\.gz\.enc$' | awk '{print $4}' | while read -r archive_key; do
            
            # Extract keyspace and table name from the clean S3 path
            local s3_path_no_host
            s3_path_no_host=$(echo "$archive_key" | sed "s#$EFFECTIVE_SOURCE_HOST/$backup_ts/##")
            local ks_dir
            ks_dir=$(echo "$s3_path_no_host" | cut -d'/' -f1)
            local table_name
            table_name=$(echo "$s3_path_no_host" | cut -d'/' -f2)

            # Look up the correct UUID-based directory name from the map
            local table_uuid_dir
            table_uuid_dir=$(echo "$SCHEMA_MAP_JSON" | jq -r ".\"${ks_dir}.${table_name}\"")
            if [ -z "$table_uuid_dir" ] || [ "$table_uuid_dir" == "null" ]; then
                log_message "WARNING: Could not find mapping for ${ks_dir}.${table_name}. Skipping archive $archive_key"
                continue
            fi
            
            # The local output directory must use the UUID
            local output_dir="$TEMP_RESTORE_DIR/$ks_dir/$table_uuid_dir"
            
            download_and_extract_table "$archive_key" "$output_dir" "$TEMP_RESTORE_DIR" "$TEMP_RESTORE_DIR"
        done
    done
    log_message "All data from backup chain downloaded and extracted to temporary directory."

    # === PHASE 3: DATA PLACEMENT AND STARTUP ===
    log_message "--- PHASE 3: FINALIZATION ---"

    log_message "7. Moving restored data from temporary dir to final data directory..."
    # rsync is safer than mv as it can be resumed.
    rsync -a "$TEMP_RESTORE_DIR/" "$CASSANDRA_DATA_DIR/"
    log_message "Data moved successfully."
    
    log_message "8. Setting correct ownership for all Cassandra directories..."
    chown -R "$CASSANDRA_USER":"$CASSANDRA_USER" "$CASSANDRA_DATA_DIR"
    chown -R "$CASSANDRA_USER":"$CASSANDRA_USER" "$CASSANDRA_COMMITLOG_DIR"
    chown -R "$CASSANDRA_USER":"$CASSANDRA_USER" "$CASSANDRA_CACHES_DIR"

    log_message "9. Starting Cassandra service..."
    systemctl start cassandra
    
    log_message "Waiting for Cassandra to initialize and come online..."
    local CASSANDRA_READY=false
    for i in {1..60}; do # Wait up to 10 minutes
        if nodetool status 2>/dev/null | grep "$LISTEN_ADDRESS" | grep -q 'UN'; then
            CASSANDRA_READY=true
            break
        fi
        log_message "Waiting for node to report UP/NORMAL... (attempt $i of 60)"
        sleep 10
    done

    if [ "$CASSANDRA_READY" = false ]; then
        log_message "ERROR: Cassandra did not become ready. Check system logs."
        log_message "The restored data is in place, but the service failed to start correctly."
        exit 1
    fi
    
    log_message "Cassandra is online and ready."
    log_message "10. Restore complete."
    log_message "The temporary directory $TEMP_RESTORE_DIR will now be removed."
    
    log_message "--- Full Restore Process Finished Successfully ---"
}


download_and_extract_table() {
    local archive_key="$1"
    local output_dir="$2"
    local temp_download_dir="$3"
    local check_path="$4"

    # Safety check before downloading this table's data
    log_message "Checking disk usage on $check_path before downloading..."
    if ! /usr/local/bin/disk-health-check.sh -p "$check_path" -w 90 -c 95; then
        log_message "ERROR: Disk usage is high. Aborting download for archive $archive_key."
        return 1
    fi

    mkdir -p "$output_dir"
    
    log_message "Downloading data for $archive_key to $output_dir"
    
    # Use clean, static temporary filenames within this function's scope.
    local temp_enc_file="$temp_download_dir/temp.tar.gz.enc"
    local temp_tar_file="$temp_download_dir/temp.tar.gz"

    # Ensure no old temp files exist from a failed previous run.
    rm -f "$temp_enc_file" "$temp_tar_file"

    if ! aws s3 cp "s3://$EFFECTIVE_S3_BUCKET/$archive_key" "$temp_enc_file"; then
        log_message "ERROR: Failed to download $archive_key."
        rm -f "$temp_enc_file" # Clean up partial download
        return 1
    fi

    if ! openssl enc -d -aes-256-cbc -salt -pbkdf2 -md sha256 -in "$temp_enc_file" -out "$temp_tar_file" -pass "file:$TMP_KEY_FILE"; then
        log_message "ERROR: Failed to decrypt $archive_key. Check encryption key and file integrity."
        rm -f "$temp_enc_file" "$temp_tar_file"
        return 1
    fi

    if ! tar -xzf "$temp_tar_file" -C "$output_dir"; then
        log_message "ERROR: Failed to extract $archive_key. Archive is likely corrupt."
        rm -f "$temp_enc_file" "$temp_tar_file"
        return 1
    fi
    
    # Final cleanup of temp files for this run.
    rm -f "$temp_enc_file" "$temp_tar_file"
    return 0
}


do_granular_restore() {
    log_message "--- Starting GRANULAR Restore for $KEYSPACE_NAME${TABLE_NAME:+.${TABLE_NAME}} ---"

    local base_output_dir
    local temp_download_dir
    local check_path

    if [ "$RESTORE_ACTION" == "download_only" ]; then
        base_output_dir="$DOWNLOAD_ONLY_PATH"
        temp_download_dir="$DOWNLOAD_ONLY_PATH"
        check_path="$DOWNLOAD_ONLY_PATH"
        log_message "Action: Download-Only. Data will be saved to $base_output_dir"
        mkdir -p "$base_output_dir"
    else # download_and_restore
        TEMP_RESTORE_DIR="${RESTORE_BASE_PATH}/restore_temp_$$"
        base_output_dir="$TEMP_RESTORE_DIR"
        temp_download_dir="$TEMP_RESTORE_DIR"
        check_path="$RESTORE_BASE_PATH"
        log_message "Action: Download & Restore. Using temporary directory $base_output_dir"
        mkdir -p "$base_output_dir"
    fi
    
    local path_to_load="$base_output_dir"

    log_message "Performing pre-flight disk usage check on $check_path..."
    if ! /usr/local/bin/disk-health-check.sh -p "$check_path" -w 80 -c 90; then
        log_message "ERROR: Insufficient disk space on the target volume. Aborting granular restore."
        exit 1
    fi
    log_message "Disk usage is sufficient to begin."

    # Download the schema mapping first
    local SCHEMA_MAP_JSON
    SCHEMA_MAP_JSON=$(aws s3 cp "s3://$EFFECTIVE_S3_BUCKET/$EFFECTIVE_SOURCE_HOST/$BASE_FULL_BACKUP/schema_mapping.json" - 2>/dev/null)
    if [ -z "$SCHEMA_MAP_JSON" ]; then
        log_message "ERROR: Cannot download schema_mapping.json for base backup $BASE_FULL_BACKUP. Aborting."
        exit 1
    fi
    log_message "Schema-to-directory mapping downloaded."

    # Step 1: Download and extract all data from the entire chain.
    for backup_ts in "${CHAIN_TO_RESTORE[@]}"; do
        log_message "Processing backup: $backup_ts"
        
        # Only list objects under the specified keyspace
        aws s3 ls --recursive "s3://$EFFECTIVE_S3_BUCKET/$EFFECTIVE_SOURCE_HOST/$backup_ts/$KEYSPACE_NAME/" | grep '\.tar\.gz\.enc$' | awk '{print $4}' | while read -r archive_key; do
            # The archive_key is now relative to the bucket, e.g., source_host/backup_ts/ks/tbl/tbl.tar.gz.enc
            
            # If a table name is specified, only process archives for that table.
            if [ -n "$TABLE_NAME" ] && [[ ! "$archive_key" =~ "/${TABLE_NAME}/" ]]; then
                continue
            fi
            
            local s3_path_no_host
            s3_path_no_host=$(echo "$archive_key" | sed "s#$EFFECTIVE_SOURCE_HOST/$backup_ts/##")
            local ks_dir
            ks_dir=$(echo "$s3_path_no_host" | cut -d'/' -f1)
            local table_name
            table_name=$(echo "$s3_path_no_host" | cut -d'/' -f2)

            # Look up the correct UUID-based directory name from the map
            local table_uuid_dir
            table_uuid_dir=$(echo "$SCHEMA_MAP_JSON" | jq -r ".\"${ks_dir}.${table_name}\"")
            if [ -z "$table_uuid_dir" ] || [ "$table_uuid_dir" == "null" ]; then
                log_message "WARNING: Could not find mapping for ${ks_dir}.${table_name}. Skipping archive $archive_key"
                continue
            fi

            local output_dir="$base_output_dir/$ks_dir/$table_uuid_dir"
            
            download_and_extract_table "$archive_key" "$output_dir" "$temp_download_dir" "$check_path"
        done
    done
    
    # Step 2: Decide on the final action.
    if [ "$RESTORE_ACTION" == "download_only" ]; then
        log_message "--- Granular Restore (Download Only) Finished Successfully ---"
        log_message "All data has been downloaded and decrypted to: $base_output_dir"
    else # download_and_restore
        log_message "All data has been downloaded. Preparing to load into cluster..."
        
        # Handle UUID mismatch for single-table restores
        if [ -n "$TABLE_NAME" ]; then
            log_message "Handling potential table UUID mismatch for granular restore of $KEYSPACE_NAME.$TABLE_NAME..."

            # Find the source directory path (with old UUID from backup)
            local source_table_dir
            source_table_dir=$(find "$path_to_load/$KEYSPACE_NAME" -maxdepth 1 -type d -name "$TABLE_NAME-*" -print -quit)
            
            if [ -z "$source_table_dir" ]; then
                log_message "ERROR: No downloaded data found for table '$TABLE_NAME' in '$path_to_load/$KEYSPACE_NAME'. Cannot proceed with restore."
                exit 1
            else
                log_message "DEBUG: Found source (downloaded) table dir: '$source_table_dir'"
                # Find the destination directory path (with live UUID)
                local live_table_dir
                live_table_dir=$(find "$CASSANDRA_DATA_DIR/$KEYSPACE_NAME" -maxdepth 1 -type d -name "$TABLE_NAME-*" -print -quit)
                
                if [ -z "$live_table_dir" ]; then
                    log_message "ERROR: Cannot find live table directory for '$KEYSPACE_NAME.$TABLE_NAME' in '$CASSANDRA_DATA_DIR'."
                    log_message "The table must exist in the cluster before you can perform a granular restore."
                    exit 1
                else
                    log_message "DEBUG: Found live table dir: '$live_table_dir'"
                    local live_table_dirname
                    live_table_dirname=$(basename "$live_table_dir")
                    
                    local source_table_dirname
                    source_table_dirname=$(basename "$source_table_dir")

                    if [ "$source_table_dirname" != "$live_table_dirname" ]; then
                        log_message "UUID mismatch detected. Renaming downloaded directory to match live table UUID."
                        log_message "Renaming '$source_table_dir' to '$(dirname "$source_table_dir")/$live_table_dirname'"
                        mv "$source_table_dir" "$(dirname "$source_table_dir")/$live_table_dirname"
                    else
                        log_message "UUIDs match. No rename necessary."
                    fi
                fi
            fi
        fi

        # The path_to_load is the directory containing the keyspace folders.
        if [ -d "$path_to_load" ] && [ -n "$(ls -A "$path_to_load")" ]; then
            log_message "Setting correct ownership on downloaded data..."
            chown -R "$CASSANDRA_USER":"$CASSANDRA_USER" "$path_to_load"

            export CASSANDRA_CONF="$CASSANDRA_CONF_DIR"
            log_message "Using Cassandra config directory: $CASSANDRA_CONF"

            local loader_cmd=("sstableloader" "--verbose" "--no-progress" "-d" "$LOADER_NODES")
            
            if [[ -n "$CASSANDRA_USER" && "$CASSANDRA_USER" != "null" ]]; then
                loader_cmd+=("-u" "$CASSANDRA_USER")
            fi
            if [[ -n "$CASSANDRA_PASSWORD" && "$CASSANDRA_PASSWORD" != "null" ]]; then
                loader_cmd+=("-pw" "$CASSANDRA_PASSWORD")
            fi

            if [ "$SSL_ENABLED" == "true" ]; then
                log_message "SSL is enabled, providing SSL options to sstableloader."
                loader_cmd+=("--ssl-storage-port" "7001")
            fi

            # Pass the parent directory containing the keyspace folder(s)
            loader_cmd+=("$path_to_load")

            log_message "The following command will be executed:"
            echo "${loader_cmd[*]}" | tee -a "$RESTORE_LOG_FILE"
            
            if "${loader_cmd[@]}"; then
                log_message "--- Granular Restore (Download & Restore) Finished Successfully ---"
            else
                log_message "ERROR: sstableloader failed. The downloaded data is still available in $path_to_load for inspection."
                exit 1
            fi
        else
            log_message "WARNING: No data was downloaded for the specified keyspace/table. Nothing to load."
        fi
    fi
}

# --- Main Execution ---

log_message "--- Starting Point-in-Time Restore Manager ---"
log_message "Target S3 Bucket: $EFFECTIVE_S3_BUCKET"
log_message "Source Hostname for Restore: $EFFECTIVE_SOURCE_HOST"

if [ "$BACKUP_BACKEND" != "s3" ]; then
    log_message "ERROR: This restore script only supports the 's3' backup backend."
    log_message "The current backup_backend is configured as '$BACKUP_BACKEND'."
    exit 1
fi

find_backup_chain

log_message "Backup chain to be restored (chronological order):"
printf " - %s\n" "${CHAIN_TO_RESTORE[@]}"
log_message "Base full backup for this chain is: $BASE_FULL_BACKUP"

if [ "$AUTO_APPROVE" = false ]; then
    read -p "Does the restore chain above look correct? Type 'yes' to proceed: " manifest_confirmation
    if [[ "$manifest_confirmation" != "yes" ]]; then
        log_message "Restore aborted by user based on chain review."
        exit 0
    fi
else
    log_message "Auto-approving restore chain via --yes flag."
fi

case $MODE in
    "full")
        do_full_restore
        ;;
    "granular")
        do_granular_restore
        ;;
    *)
        log_message "INTERNAL ERROR: Invalid mode detected or no mode specified."
        usage
        exit 1
        ;;
esac

exit 0

    