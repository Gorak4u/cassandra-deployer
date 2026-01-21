#!/bin/bash
# Restores a Cassandra node from backups in S3 to a specific point in time.
# This script can combine a full backup with subsequent incremental backups.
# Supports full node restore, granular keyspace/table restore, and schema-only extraction.

set -euo pipefail

# --- Configuration & Input ---
CONFIG_FILE="/etc/backup/config.json"
HOSTNAME=$(hostname -s)
RESTORE_LOG_FILE="/var/log/cassandra/restore.log"

# --- CLI Arguments (to be parsed) ---
TARGET_DATE=""
KEYSPACE_NAME=""
TABLE_NAME=""
MODE="" # Will be set to 'granular', 'full', or 'schema'
RESTORE_ACTION="" # For granular: 'download_only' or 'download_and_restore'
DOWNLOAD_ONLY_PATH="/var/lib/cassandra/restore"

# --- Logging ---
log_message() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$RESTORE_LOG_FILE"
}

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
    log_message "  --download-only                      Download and decrypt data to $DOWNLOAD_ONLY_PATH."
    log_message "  --download-and-restore             Download data and load it into the cluster via sstableloader."
    exit 1
}

# --- Pre-flight Checks ---
if [ "$(id -u)" -ne 0 ]; then
    log_message "ERROR: This script must be run as root."
    exit 1
fi

for tool in jq aws sstableloader openssl; do
    if ! command -v $tool &>/dev/null; then
        log_message "ERROR: Required tool '$tool' is not installed or not in PATH."
        exit 1
    fi
done

if [ ! -f "$CONFIG_FILE" ]; then
    log_message "ERROR: Backup configuration file not found at $CONFIG_FILE"
    exit 1
fi

# --- Source configuration from JSON ---
S3_BUCKET_NAME=$(jq -r '.s3_bucket_name' "$CONFIG_FILE")
CASSANDRA_DATA_DIR=$(jq -r '.cassandra_data_dir' "$CONFIG_FILE")
CASSANDRA_COMMITLOG_DIR=$(jq -r '.commitlog_dir' "$CONFIG_FILE")
CASSANDRA_CACHES_DIR=$(jq -r '.saved_caches_dir' "$CONFIG_FILE")
LISTEN_ADDRESS=$(jq -r '.listen_address' "$CONFIG_FILE")
SEEDS=$(jq -r '.seeds_list | join(",")' "$CONFIG_FILE")
CASSANDRA_USER="cassandra"

# Determine node list for sstableloader. Use seeds if available, otherwise localhost.
if [ -n "$SEEDS" ]; then
    LOADER_NODES="$SEEDS"
else
    LOADER_NODES="$LISTEN_ADDRESS"
fi

# --- Argument Parsing ---
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

# Create a temporary file for the encryption key and set a trap to clean it up
TMP_KEY_FILE=$(mktemp)
chmod 600 "$TMP_KEY_FILE"
trap 'rm -f "$TMP_KEY_FILE"' EXIT

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
    
    local cqlsh_config="/root/.cassandra/cqlshrc"
    local cqlsh_ssl_opt=""
    if [ -f "$cqlsh_config" ] && grep -q '\[ssl\]' "$cqlsh_config"; then
        cqlsh_ssl_opt="--ssl"
    fi

    local schema_s3_path="s3://$S3_BUCKET_NAME/$HOSTNAME/$BASE_FULL_BACKUP/schema.cql"
    log_message "Downloading schema from $schema_s3_path"

    if aws s3 cp "$schema_s3_path" "/tmp/schema_restore.cql"; then
        log_message "SUCCESS: Schema extracted to /tmp/schema_restore.cql"
        log_message "Please review this file, then apply it to your cluster using: cqlsh ${cqlsh_ssl_opt} -f /tmp/schema_restore.cql"
    else
        log_message "ERROR: Failed to download schema.cql from the backup. The full backup may be corrupted or missing its schema file."
        exit 1
    fi
    log_message "--- Schema-Only Restore Finished ---"
}


do_full_restore() {
    log_message "--- Starting FULL DESTRUCTIVE Node Restore ---"
    log_message "This will restore the node to the state at the end of the last backup in the chain."
    log_message "WARNING: This is a DESTRUCTIVE operation. It will:"
    log_message "1. STOP the Cassandra service."
    log_message "2. WIPE ALL DATA AND COMMITLOGS from $CASSANDRA_DATA_DIR and $CASSANDRA_COMMITLOG_DIR."
    log_message "3. RESTORE data from the backup chain."
    read -p "Are you absolutely sure you want to PERMANENTLY DELETE ALL DATA on this node? Type 'yes': " confirmation
    if [[ "$confirmation" != "yes" ]]; then
        log_message "Restore aborted by user."
        exit 0
    fi

    log_message "1. Stopping Cassandra service..."
    systemctl stop cassandra

    log_message "2. Wiping old data..."
    rm -rf "$CASSANDRA_DATA_DIR"/*
    rm -rf "$CASSANDRA_COMMITLOG_DIR"/*
    rm -rf "$CASSANDRA_CACHES_DIR"/*
    log_message "Old directories cleaned."

    log_message "3. Downloading and extracting data from backup chain..."
    for backup_ts in "${CHAIN_TO_RESTORE[@]}"; do
        log_message "Processing backup: $backup_ts"
        local table_archives
        table_archives=$(aws s3 ls --recursive "s3://$S3_BUCKET_NAME/$HOSTNAME/$backup_ts/" | grep -E '(\.tar\.enc)$' | awk '{print $4}')

        for archive_key in $table_archives; do
            local s3_path="s3://$S3_BUCKET_NAME/$archive_key"
            local ks_table_part
            ks_table_part=$(dirname "$archive_key" | sed "s#^$HOSTNAME/$backup_ts/##")
            local target_dir="$CASSANDRA_DATA_DIR/$ks_table_part"

            log_message "Restoring to $target_dir from $s3_path"
            mkdir -p "$target_dir"
            
            if ! aws s3 cp "$s3_path" - | openssl enc -d -aes-256-cbc -pass "file:$TMP_KEY_FILE" | tar -xzf - -C "$target_dir"; then
                 log_message "ERROR: Failed to download or extract $archive_key. Aborting restore."
                 exit 1
            fi
        done
    done
    log_message "All data from backup chain extracted."
    
    log_message "4. Setting permissions..."
    chown -R "$CASSANDRA_USER:$CASSANDRA_USER" "$CASSANDRA_DATA_DIR"
    chown -R "$CASSANDRA_USER:$CASSANDRA_USER" "$CASSANDRA_COMMITLOG_DIR"
    chown -R "$CASSANDRA_USER:$CASSANDRA_USER" "$CASSANDRA_CACHES_DIR"

    log_message "5. Starting Cassandra service..."
    systemctl start cassandra
    log_message "Service started. It may take a while for the node to initialize and join the cluster."
    log_message "Monitor nodetool status and system logs."
    log_message "--- Full Restore Process Finished ---"
}


download_and_extract_table() {
    local backup_ts="$1"
    local ks_name="$2"
    local tbl_name="$3"
    local output_base_dir="$4"

    local archive_path_base="$HOSTNAME/$backup_ts/$ks_name/$tbl_name"
    local archive_path_full="$archive_path_base/$tbl_name.tar.enc"
    local archive_path_incr="$archive_path_base/incremental.tar.enc"
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
    local table_output_dir="$output_base_dir/$ks_name/$tbl_name/$(basename "$archive_to_download" .tar.enc)"
    mkdir -p "$table_output_dir"
    
    log_message "Downloading data for $ks_name.$tbl_name from $archive_to_download"
    
    if ! aws s3 cp "s3://$S3_BUCKET_NAME/$archive_to_download" - | openssl enc -d -aes-256-cbc -pass "file:$TMP_KEY_FILE" | tar -xzf - -C "$table_output_dir"; then
        log_message "ERROR: Failed to download or extract $archive_to_download."
        rm -rf "$table_output_dir" # Clean up partial data
        return 1
    fi
    
    echo "$table_output_dir"
    return 0
}


do_granular_restore() {
    log_message "--- Starting GRANULAR Restore for $KEYSPACE_NAME${TABLE_NAME:+.${TABLE_NAME}} ---"
    
    local base_output_dir
    local temp_restore_dir="/tmp/restore_$$"
    
    if [ "$RESTORE_ACTION" == "download_only" ]; then
        base_output_dir="$DOWNLOAD_ONLY_PATH"
        log_message "Action: Download-Only. Data will be saved to $base_output_dir"
        mkdir -p "$base_output_dir"
        trap 'rm -f "$TMP_KEY_FILE"' EXIT
    else # download_and_restore
        base_output_dir="$temp_restore_dir"
        log_message "Action: Download & Restore. Using temporary directory $base_output_dir"
        mkdir -p "$base_output_dir"
        trap 'rm -f "$TMP_KEY_FILE"; rm -rf "$base_output_dir"' EXIT
    fi
    
    for backup_ts in "${CHAIN_TO_RESTORE[@]}"; do
        log_message "Processing backup: $backup_ts"
        
        if [ -n "$TABLE_NAME" ]; then
            local restored_data_path
            restored_data_path=$(download_and_extract_table "$backup_ts" "$KEYSPACE_NAME" "$TABLE_NAME" "$base_output_dir")
            
            if [ -z "$restored_data_path" ]; then
                continue
            fi
            
            if [ "$RESTORE_ACTION" == "download_and_restore" ]; then
                log_message "Loading data for $KEYSPACE_NAME.$TABLE_NAME into cluster..."
                if sstableloader -d "$LOADER_NODES" "$restored_data_path"; then
                    log_message "Successfully loaded data from backup $backup_ts for table $TABLE_NAME."
                    rm -rf "$restored_data_path"
                else
                    log_message "ERROR: sstableloader failed for data from backup $backup_ts for table $TABLE_NAME. Aborting."
                    exit 1
                fi
            fi
        else
            # Restore all tables in the keyspace
            log_message "Discovering all tables in keyspace '$KEYSPACE_NAME' for backup '$backup_ts'..."
            local tables_in_backup
            tables_in_backup=$(aws s3 ls "s3://$S3_BUCKET_NAME/$HOSTNAME/$backup_ts/$KEYSPACE_NAME/" | awk '{print $2}' | sed 's/\///')
            
            if [ -z "$tables_in_backup" ]; then
                log_message "No tables found for keyspace '$KEYSPACE_NAME' in backup '$backup_ts'. Skipping."
                continue
            fi

            for table_in_ks in $tables_in_backup; do
                local restored_data_path
                restored_data_path=$(download_and_extract_table "$backup_ts" "$KEYSPACE_NAME" "$table_in_ks" "$base_output_dir")

                if [ -z "$restored_data_path" ]; then
                    continue
                fi

                if [ "$RESTORE_ACTION" == "download_and_restore" ]; then
                    log_message "Loading data for $KEYSPACE_NAME.$table_in_ks into cluster..."
                    if sstableloader -d "$LOADER_NODES" "$restored_data_path"; then
                        log_message "Successfully loaded data from backup $backup_ts for table $table_in_ks."
                        rm -rf "$restored_data_path"
                    else
                        log_message "ERROR: sstableloader failed for data from backup $backup_ts for table $table_in_ks. Aborting."
                        exit 1
                    fi
                fi
            done
        fi
    done
    
    if [ "$RESTORE_ACTION" == "download_only" ]; then
        log_message "--- Granular Restore (Download Only) Finished Successfully ---"
        log_message "All data has been downloaded and decrypted to: $base_output_dir"
    else
        log_message "--- Granular Restore (Download & Restore) Finished Successfully ---"
    fi
}

# --- Main Execution ---

log_message "--- Starting Point-in-Time Restore Manager ---"
find_backup_chain

log_message "Backup chain to be restored (chronological order):"
printf " - %s\n" "${CHAIN_TO_RESTORE[@]}"
log_message "Base full backup for this chain is: $BASE_FULL_BACKUP"

read -p "Does the restore chain above look correct? Type 'yes' to proceed: " manifest_confirmation
if [[ "$manifest_confirmation" != "yes" ]]; then
    log_message "Restore aborted by user based on chain review."
    exit 0
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
