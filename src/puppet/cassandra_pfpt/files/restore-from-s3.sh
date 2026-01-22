
#!/bin/bash
# Restores a Cassandra node from backups in S3 to a specific point in time.
# This script can combine a full backup with subsequent incremental backups.
# Supports full node restore, granular keyspace/table restore, and schema-only extraction.

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

for tool in jq aws sstableloader openssl pgrep ps cqlsh /usr/local/bin/disk-health-check.sh; do
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
    log_message "  --schema-only                        Extracts only the schema from the relevant full backup."
    log_message "  --keyspace <ks> [--table <table>]  Targets a specific keyspace or table for a granular restore (requires an action)."
    log_message ""
    log_message "Actions for Granular Restore (required if --keyspace is used):"
    log_message "  --download-only                      Download and decrypt data to a derived path inside /var/lib/cassandra."
    log_message "  --download-and-restore             Download data and load it into the cluster via sstableloader."
    log_message ""
    log_message "Automation:"
    log_message "  --yes                                Skips all interactive confirmation prompts. Use with caution."
    exit 1
}


# --- Source configuration from JSON ---
S3_BUCKET_NAME=$(jq -r '.s3_bucket_name' "$CONFIG_FILE")
CASSANDRA_DATA_DIR=$(jq -r '.cassandra_data_dir' "$CONFIG_FILE")
CASSANDRA_CONF_DIR=$(jq -r '.config_dir_path' "$CONFIG_FILE")
JVM_OPTIONS_FILE="$CASSANDRA_CONF_DIR/jvm-server.options"
CASSANDRA_COMMITLOG_DIR=$(jq -r '.commitlog_dir' "$CONFIG_FILE")
CASSANDRA_CACHES_DIR=$(jq -r '.saved_caches_dir' "$CONFIG_FILE")
LISTEN_ADDRESS=$(jq -r '.listen_address' "$CONFIG_FILE")
SEEDS=$(jq -r '.seeds_list | join(",")' "$CONFIG_FILE")
CASSANDRA_USER=$(jq -r '.cassandra_user // "cassandra"' "$CONFIG_FILE")
CASSANDRA_PASSWORD=$(jq -r '.cassandra_password' "$CONFIG_FILE")
SSL_ENABLED=$(jq -r '.ssl_enabled // "false"' "$CONFIG_FILE")
BACKUP_BACKEND=$(jq -r '.backup_backend // "s3"' "$CONFIG_FILE")

# Validate essential configuration
if [ -z "$CASSANDRA_CONF_DIR" ] || [ "$CASSANDRA_CONF_DIR" == "null" ]; then log_message "ERROR: 'config_dir_path' is not set in $CONFIG_FILE."; exit 1; fi
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
MODE="" # Will be set to 'granular', 'full', or 'schema'
RESTORE_ACTION="" # For granular: 'download_only' or 'download_and_restore'
AUTO_APPROVE=false

if [ "$#" -eq 0 ]; then
    usage
fi

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --date) TARGET_DATE="$2"; shift ;;
        --keyspace) KEYSPACE_NAME="$2"; shift ;;
        --table) TABLE_NAME="$2"; shift ;;
        --full-restore) MODE="full" ;;
        --schema-only) MODE="schema" ;;
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
    if [ -f "$JVM_OPTIONS_FILE" ]; then
      log_message "Ensuring schema replay flag is removed from JVM options..."
      sed -i '/-Dcassandra.replay_schema_from_file/d' "$JVM_OPTIONS_FILE"
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

    log_message "Listing available backups from S3..."
    local all_backups
    all_backups=$(aws s3 ls "s3://$S3_BUCKET_NAME/$HOSTNAME/" | awk '{print $2}' | sed 's/\///' || true)

    if [ -z "$all_backups" ]; then
        log_message "ERROR: No backups found for host '$HOSTNAME' in bucket '$S3_BUCKET_NAME'."
        exit 1
    fi

    local eligible_backups=()
    for backup_ts in $all_backups; do
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
        manifest=$(aws s3 cp "s3://$S3_BUCKET_NAME/$HOSTNAME/$backup_ts/backup_manifest.json" - 2>/dev/null || continue)
        
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

do_schema_restore() {
    log_message "--- Starting Schema-Only Restore from Full Backup: $BASE_FULL_BACKUP ---"
    
    local cqlsh_cmd_parts=("cqlsh")
    if [ "$SSL_ENABLED" == "true" ]; then
        cqlsh_cmd_parts+=("--ssl")
    fi
    cqlsh_cmd_parts+=("-u" "$CASSANDRA_USER" "-p" "$CASSANDRA_PASSWORD")

    local schema_s3_path="s3://$S3_BUCKET_NAME/$HOSTNAME/$BASE_FULL_BACKUP/schema.cql"
    log_message "Downloading schema from $schema_s3_path"

    if aws s3 cp "$schema_s3_path" "/tmp/schema_restore.cql"; then
        log_message "SUCCESS: Schema extracted to /tmp/schema_restore.cql"
        log_message "Please review this file, then apply it to your cluster using: ${cqlsh_cmd_parts[*]} -f /tmp/schema_restore.cql"
    else
        log_message "ERROR: Failed to download schema.cql from the backup. The full backup may be corrupted or missing its schema file."
        exit 1
    fi
    log_message "--- Schema-Only Restore Finished ---"
}


do_full_restore() {
    log_message "--- Starting FULL DESTRUCTIVE Node Restore ---"
    log_message "This will restore the node using sstableloader for maximum reliability."
    log_message "WARNING: This is a DESTRUCTIVE operation. It will:"
    log_message "1. STOP the Cassandra service."
    log_message "2. WIPE ALL DATA AND COMMITLOGS from $CASSANDRA_DATA_DIR and $CASSANDRA_COMMITLOG_DIR."
    log_message "3. RESTORE data from the backup chain into a temporary staging area."
    log_message "4. START Cassandra with the restored schema."
    log_message "5. LOAD the staged data using sstableloader."
    
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
    
    log_message "3. Setting correct ownership for Cassandra directories..."
    chown -R cassandra:cassandra "$CASSANDRA_DATA_DIR"
    chown -R cassandra:cassandra "$CASSANDRA_COMMITLOG_DIR"
    chown -R cassandra:cassandra "$CASSANDRA_CACHES_DIR"

    TEMP_RESTORE_DIR="${RESTORE_BASE_PATH}/restore_staging_$$"
    log_message "4. Creating temporary staging directory: $TEMP_RESTORE_DIR"
    mkdir -p "$TEMP_RESTORE_DIR"

    # === PHASE 2: DATA STAGING (OFFLINE) ===
    log_message "--- PHASE 2: DATA STAGING ---"
    
    # 2a. Download and Stage Schema
    local schema_s3_path="s3://$S3_BUCKET_NAME/$HOSTNAME/$BASE_FULL_BACKUP/schema.cql"
    local staged_schema_path="$TEMP_RESTORE_DIR/schema.cql"
    log_message "5. Downloading schema to staging area..."
    if ! aws s3 cp "$schema_s3_path" "$staged_schema_path"; then
        log_message "ERROR: Failed to download schema.cql. Aborting."
        exit 1
    fi
    log_message "Schema staged successfully."

    # 2b. Download and Stage Data
    log_message "6. Downloading and extracting all data from backup chain to staging area..."
    for backup_ts in "${CHAIN_TO_RESTORE[@]}"; do
        log_message "Processing backup: $backup_ts"
        local table_archives
        table_archives=$(aws s3 ls --recursive "s3://$S3_BUCKET_NAME/$HOSTNAME/$backup_ts/" | grep -E '(\.tar\.gz\.enc)$' | awk '{print $4}')

        for archive_key in $table_archives; do
            local s3_path="s3://$S3_BUCKET_NAME/$archive_key"
            local ks_table_part
            ks_table_part=$(dirname "$archive_key" | sed "s#^$HOSTNAME/$backup_ts/##")
            local table_name
            table_name=$(basename "$ks_table_part")
            local ks_name
            ks_name=$(dirname "$ks_table_part")

            download_and_extract_table "$backup_ts" "$ks_name" "$table_name" "$TEMP_RESTORE_DIR" "$TEMP_RESTORE_DIR" "$RESTORE_BASE_PATH"
        done
    done
    log_message "All data from backup chain extracted to staging area."

    # === PHASE 3: LOADING AND FINALIZATION (ONLINE) ===
    log_message "--- PHASE 3: LOADING AND FINALIZATION ---"

    log_message "7. Temporarily disabling authentication for restore..."
    local yaml_file="$CASSANDRA_CONF_DIR/cassandra.yaml"
    sed -i 's/authenticator:.*/authenticator: AllowAllAuthenticator/' "$yaml_file"
    sed -i 's/authorizer:.*/authorizer: AllowAllAuthorizer/' "$yaml_file"

    log_message "8. Preparing Cassandra for schema replay..."
    # Clean up any previous flags first
    sed -i '/-Dcassandra.replay_schema_from_file/d' "$JVM_OPTIONS_FILE"
    # Add the new flag
    echo "-Dcassandra.replay_schema_from_file=$staged_schema_path" >> "$JVM_OPTIONS_FILE"

    log_message "9. Starting Cassandra service with schema replay..."
    systemctl start cassandra
    
    log_message "Waiting for Cassandra to initialize and join the cluster..."
    local CASSANDRA_READY=false
    for i in {1..60}; do # Wait up to 10 minutes
        # Use nodetool as the source of truth. It will fail if the node is not up.
        if nodetool status | grep "$LISTEN_ADDRESS" | grep -q 'UN'; then
            CASSANDRA_READY=true
            break
        fi
        log_message "Waiting for node to report UP/NORMAL... (attempt $i of 60)"
        sleep 10
    done

    # Cleanup the JVM flag regardless of whether the node came up, to prevent issues on next restart
    log_message "Removing schema replay flag from JVM options..."
    sed -i '/-Dcassandra.replay_schema_from_file/d' "$JVM_OPTIONS_FILE"

    if [ "$CASSANDRA_READY" = false ]; then
        log_message "ERROR: Cassandra did not become ready (UN status). Check system logs."
        log_message "Restoring authentication settings in cassandra.yaml before exiting..."
        sed -i 's/authenticator:.*/authenticator: PasswordAuthenticator/' "$yaml_file"
        sed -i 's/authorizer:.*/authorizer: CassandraAuthorizer/' "$yaml_file"
        exit 1
    fi
    log_message "Cassandra is ready. Schema has been applied."

    log_message "10. Loading data into cluster with sstableloader..."
    
    export CASSANDRA_CONF="$CASSANDRA_CONF_DIR"
    log_message "Using Cassandra config directory: $CASSANDRA_CONF"
    
    local loader_cmd=("sstableloader" "-d" "${LOADER_NODES}")
    
    log_message "Authentication is disabled, running sstableloader without credentials."

    if [ "$SSL_ENABLED" == "true" ]; then
        log_message "SSL is enabled, providing SSL options to sstableloader."
        # Note: sstableloader uses the same ports as nodetool. 7001 is standard for SSL storage.
        loader_cmd+=("--ssl-storage-port" "7001")
    fi

    # Add the staging directory as the source for the loader
    loader_cmd+=("$TEMP_RESTORE_DIR")
    
    log_message "Executing: ${loader_cmd[*]}"
    if ! eval "${loader_cmd[*]}"; then
        log_message "ERROR: sstableloader failed. The cluster may be partially restored."
        log_message "The staged data is still available in $TEMP_RESTORE_DIR for manual inspection and reloading."
        # Still need to re-enable auth before exiting
        systemctl stop cassandra
        sed -i 's/authenticator:.*/authenticator: PasswordAuthenticator/' "$yaml_file"
        sed -i 's/authorizer:.*/authorizer: CassandraAuthorizer/' "$yaml_file"
        exit 1
    fi

    log_message "sstableloader completed successfully."
    log_message "11. Restore complete. Finalizing authentication settings."
    
    log_message "Stopping Cassandra to re-enable authentication."
    systemctl stop cassandra

    log_message "Restoring original authentication settings..."
    sed -i 's/authenticator:.*/authenticator: PasswordAuthenticator/' "$yaml_file"
    sed -i 's/authorizer:.*/authorizer: CassandraAuthorizer/' "$yaml_file"

    log_message "Starting Cassandra in normal mode..."
    systemctl start cassandra
    
    log_message "Waiting for node to come back online with authentication enabled..."
    local CASSANDRA_FINAL_READY=false
    for i in {1..30}; do
        # Use cqlsh with proper credentials as the final check
        local cqlsh_cmd_parts=("cqlsh")
        if [ "$SSL_ENABLED" == "true" ]; then
            cqlsh_cmd_parts+=("--ssl")
        fi
        cqlsh_cmd_parts+=("-u" "$CASSANDRA_USER" "-p" "$CASSANDRA_PASSWORD")

        if "${cqlsh_cmd_parts[@]}" -e "SELECT cluster_name from system.local;" > /dev/null 2>&1; then
            CASSANDRA_FINAL_READY=true
            break
        fi
        log_message "Waiting for successful CQL connection... (attempt $i of 30)"
        sleep 10
    done

    if [ "$CASSANDRA_FINAL_READY" = false ]; then
        log_message "WARNING: Node did not respond to authenticated CQL query after restart. Please check logs manually."
    else
        log_message "Node is online and responding to authenticated queries."
    fi

    log_message "The staging directory $TEMP_RESTORE_DIR will now be removed."
    # The trap will handle the final cleanup of the staging directory.
    
    log_message "--- Full Restore Process Finished Successfully ---"
}


download_and_extract_table() {
    local backup_ts="$1"
    local ks_name="$2"
    local tbl_name="$3"
    local output_base_dir="$4"
    local temp_download_dir="$5"
    local check_path="$6"

    # Safety check before downloading this table's data
    log_message "Checking disk usage on $check_path before downloading..."
    if ! /usr/local/bin/disk-health-check.sh -p "$check_path" -w 90 -c 95; then
        log_message "ERROR: Disk usage is high. Aborting download for $ks_name.$tbl_name."
        return 1
    fi

    local archive_path_base="$HOSTNAME/$backup_ts/$ks_name/$tbl_name"
    # New file extension
    local archive_path_full="$archive_path_base/$tbl_name.tar.gz.enc"
    local archive_path_incr="$archive_path_base/incremental.tar.gz.enc"
    local archive_to_download=""

    if aws s3api head-object --bucket "$S3_BUCKET_NAME" --key "$archive_path_full" >/dev/null 2>&1; then
        archive_to_download="$archive_path_full"
    elif aws s3api head-object --bucket "$S3_BUCKET_NAME" --key "$archive_path_incr" >/dev/null 2>&1; then
        archive_to_download="$archive_path_incr"
    else
        log_message "INFO: No data for $ks_name.$tbl_name found in backup $backup_ts. Skipping."
        return 1
    fi

    # The actual output dir for this specific table's data
    local table_output_dir="$output_base_dir/$ks_name/$tbl_name"
    mkdir -p "$table_output_dir"
    
    log_message "Downloading data for $ks_name.$tbl_name from $archive_to_download"
    
    local temp_enc_file="$temp_download_dir/$ks_name.$tbl_name.$$.tar.gz.enc"
    local temp_tar_file="$temp_download_dir/$ks_name.$tbl_name.$$.tar.gz"

    if ! aws s3 cp "s3://$S3_BUCKET_NAME/$archive_to_download" "$temp_enc_file"; then
        log_message "ERROR: Failed to download $archive_to_download."
        return 1
    fi

    if ! openssl enc -d -aes-256-cbc -pbkdf2 -in "$temp_enc_file" -out "$temp_tar_file" -pass "file:$TMP_KEY_FILE"; then
        log_message "ERROR: Failed to decrypt $archive_to_download. Check encryption key and file integrity."
        rm -f "$temp_enc_file"
        return 1
    fi

    if ! tar -xzf "$temp_tar_file" -C "$table_output_dir"; then
        log_message "ERROR: Failed to extract $archive_to_download. Archive is likely corrupt."
        rm -f "$temp_enc_file" "$temp_tar_file"
        return 1
    fi
    
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
    
    log_message "Performing pre-flight disk usage check on $check_path..."
    if ! /usr/local/bin/disk-health-check.sh -p "$check_path" -w 80 -c 90; then
        log_message "ERROR: Insufficient disk space on the target volume. Aborting granular restore."
        exit 1
    fi
    log_message "Disk usage is sufficient to begin."

    # Step 1: Download and extract all data from the entire chain.
    for backup_ts in "${CHAIN_TO_RESTORE[@]}"; do
        log_message "Processing backup: $backup_ts"
        
        if [ -n "$TABLE_NAME" ]; then
            # If a specific table is requested, just download it.
            download_and_extract_table "$backup_ts" "$KEYSPACE_NAME" "$TABLE_NAME" "$base_output_dir" "$temp_download_dir" "$check_path"
        else
            # If a whole keyspace is requested, discover and download all tables.
            log_message "Discovering all tables in keyspace '$KEYSPACE_NAME' for backup '$backup_ts'..."
            local tables_in_backup
            tables_in_backup=$(aws s3 ls "s3://$S3_BUCKET_NAME/$HOSTNAME/$backup_ts/$KEYSPACE_NAME/" | awk '{print $2}' | sed 's/\///')
            
            if [ -z "$tables_in_backup" ]; then
                log_message "No tables found for keyspace '$KEYSPACE_NAME' in backup '$backup_ts'. Skipping."
                continue
            fi

            for table_in_ks in $tables_in_backup; do
                download_and_extract_table "$backup_ts" "$KEYSPACE_NAME" "$table_in_ks" "$base_output_dir" "$temp_download_dir" "$check_path"
            done
        fi
    done
    
    # Step 2: Decide on the final action.
    if [ "$RESTORE_ACTION" == "download_only" ]; then
        log_message "--- Granular Restore (Download Only) Finished Successfully ---"
        log_message "All data has been downloaded and decrypted to: $base_output_dir"
    else # download_and_restore
        log_message "All data has been downloaded. Preparing to load into cluster..."
        
        local path_to_load="$base_output_dir/$KEYSPACE_NAME"
        
        if [ -n "$TABLE_NAME" ]; then
            path_to_load="$path_to_load/$TABLE_NAME"
        fi

        if [ -d "$path_to_load" ]; then
            log_message "Loading data from path: $path_to_load"
            
            export CASSANDRA_CONF="$CASSANDRA_CONF_DIR"
            log_message "Using Cassandra config directory: $CASSANDRA_CONF"
            
            local loader_cmd=("sstableloader" "-d" "${LOADER_NODES}")
            
            log_message "Using username '$CASSANDRA_USER' for sstableloader."
            loader_cmd+=("-u" "$CASSANDRA_USER" "-pw" "$CASSANDRA_PASSWORD")

            if [ "$SSL_ENABLED" == "true" ]; then
                log_message "SSL is enabled, providing SSL options to sstableloader."
                loader_cmd+=("--ssl-storage-port" "7001")
            fi

            loader_cmd+=("$path_to_load")

            log_message "Executing: ${loader_cmd[*]}"
            
            if eval "${loader_cmd[*]}"; then
                log_message "--- Granular Restore (Download & Restore) Finished Successfully ---"
            else
                log_message "ERROR: sstableloader failed. The downloaded data is still available in $base_output_dir for inspection."
                exit 1
            fi
        else
            log_message "WARNING: No data was downloaded for the specified keyspace/table. Nothing to load."
        fi
    fi
}

# --- Main Execution ---

log_message "--- Starting Point-in-Time Restore Manager ---"

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
    "schema")
        do_schema_restore
        ;;
    "full")
        do_full_restore
        ;;
    "granular")
        do_granular_restore
        ;;
    *)
        log_message "INTERNAL ERROR: Invalid mode detected."
        exit 1
        ;;
esac

exit 0

    