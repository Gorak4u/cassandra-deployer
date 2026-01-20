#!/bin/bash
# Restores a Cassandra node from a specified backup in S3.
# Supports full node restore, granular keyspace/table restore, and schema-only extraction.

set -euo pipefail

# --- Configuration & Input ---
CONFIG_FILE="/etc/backup/config.json"
HOSTNAME=$(hostname -s)
RESTORE_LOG_FILE="/var/log/cassandra/restore.log"
BACKUP_ID=""
KEYSPACE_NAME=""
TABLE_NAME=""

# --- Logging ---
log_message() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$RESTORE_LOG_FILE"
}

# --- Usage ---
usage() {
    log_message "Usage: $0 [mode] [backup_id] [keyspace] [table]"
    log_message "Modes:"
    log_message "  Full Restore (destructive): $0 <backup_id>"
    log_message "  Granular Restore:           $0 <backup_id> <keyspace_name> [table_name]"
    log_message "  Schema-Only Restore:        $0 --schema-only <backup_id>"
    exit 1
}


# --- Pre-flight Checks ---
if [ "$(id -u)" -ne 0 ]; then
    log_message "ERROR: This script must be run as root."
    exit 1
fi

for tool in jq aws sstableloader; do
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
BACKUP_BACKEND=$(jq -r '.backup_backend // "s3"' "$CONFIG_FILE")
CASSANDRA_DATA_DIR=$(jq -r '.cassandra_data_dir' "$CONFIG_FILE")
CASSANDRA_COMMITLOG_DIR=$(jq -r '.commitlog_dir' "$CONFIG_FILE")
CASSANDRA_CACHES_DIR=$(jq -r '.saved_caches_dir' "$CONFIG_FILE")
LISTEN_ADDRESS=$(jq -r '.listen_address' "$CONFIG_FILE")
SEEDS=$(jq -r '.seeds_list | join(",")' "$CONFIG_FILE")
CASSANDRA_USER="cassandra" # Usually static

# Determine node list for sstableloader. Use seeds if available, otherwise localhost.
if [ -n "$SEEDS" ]; then
    LOADER_NODES="$SEEDS"
else
    LOADER_NODES="$LISTEN_ADDRESS"
fi


# --- Function for Schema-Only Restore ---
do_schema_restore() {
    local MANIFEST_JSON="$1"
    
    local CQLSH_CONFIG="/root/.cassandra/cqlshrc"
    local CQLSH_SSL_OPT=""
    if [ -f "$CQLSH_CONFIG" ] && grep -q '\[ssl\]' "$CQLSH_CONFIG"; then
        CQLSH_SSL_OPT="--ssl"
    fi

    log_message "--- Starting Schema-Only Restore for Backup ID: $BACKUP_ID ---"

    log_message "Downloading backup to extract schema..."
    if [ "$BACKUP_BACKEND" != "s3" ]; then
        log_message "ERROR: Cannot restore from backend '$BACKUP_BACKEND'. This script only supports 's3'."
        exit 1
    fi
    if aws s3 cp "$S3_PATH" - | tar -xzf - --to-stdout schema.cql > /tmp/schema.cql 2>/dev/null; then
        log_message "SUCCESS: Schema extracted to /tmp/schema.cql"
        log_message "Please review this file, then apply it to your cluster using: cqlsh -u <user> -p <password> ${CQLSH_SSL_OPT} -f /tmp/schema.cql"
    else
        log_message "ERROR: Failed to extract schema.cql from the backup. The backup may be corrupted or may not contain a schema file."
        exit 1
    fi
    log_message "--- Schema-Only Restore Finished ---"
}


# --- Function for Full Node Restore ---
do_full_restore() {
    local MANIFEST_JSON="$1"
    local CASSANDRA_YAML_FILE="/etc/cassandra/conf/cassandra.yaml"
    local JVM_OPTIONS_FILE="/etc/cassandra/conf/jvm-server.options"

    # This trap ensures that temporary restore flags are *always* removed on exit.
    cleanup_restore_configs() {
        log_message "INFO: Cleaning up temporary restore configurations from YAML and JVM options..."
        sed -i '/^num_tokens:/d' "$CASSANDRA_YAML_FILE"
        sed -i '/^initial_token:/d' "$CASSANDRA_YAML_FILE"
        sed -i '/cassandra.replace_address_first_boot/d' "$JVM_OPTIONS_FILE"
    }
    trap cleanup_restore_configs EXIT

    log_message "--- Starting FULL DESTRUCTIVE Node Restore for Backup ID: $BACKUP_ID ---"
    log_message "WARNING: This is a DESTRUCTIVE operation. It will:"
    log_message "1. STOP the Cassandra service."
    log_message "2. WIPE ALL DATA AND COMMITLOGS from $CASSANDRA_DATA_DIR and $CASSANDRA_COMMITLOG_DIR."
    log_message "3. RESTORE data from the backup."
    log_message "4. RESTART the service, potentially joining a cluster or starting as a first node."
    read -p "Are you absolutely sure you want to PERMANENTLY DELETE ALL DATA on this node? Type 'yes': " confirmation
    if [[ "$confirmation" != "yes" ]]; then
        log_message "Restore aborted by user."
        exit 0
    fi

    log_message "1. Stopping Cassandra service..."
    systemctl stop cassandra

    log_message "2. Performing pre-restore disk space check..."
    if ! /usr/local/bin/disk-health-check.sh -p "$CASSANDRA_DATA_DIR" -c 20; then
        exit_code=${?}
        if [ $exit_code -eq 2 ]; then
            log_message "ERROR: CRITICAL lack of disk space. Restore cannot proceed."
            log_message "Please free up space on the data volume and try again."
            log_message "Aborting restore and restarting Cassandra service."
            systemctl start cassandra
            exit 1
        fi
        log_message "WARNING: Disk space is low. Continuing with restore, but monitor closely."
    fi
    log_message "Disk space check passed."

    log_message "3. Cleaning old directories..."
    rm -rf "$CASSANDRA_DATA_DIR"/*
    rm -rf "$CASSANDRA_COMMITLOG_DIR"/*
    rm -rf "$CASSANDRA_CACHES_DIR"/*
    log_message "Old directories cleaned."

    log_message "4. Downloading and extracting backup..."
    if [ "$BACKUP_BACKEND" != "s3" ]; then
        log_message "ERROR: Cannot restore from backend '$BACKUP_BACKEND'. This script only supports 's3'."
        exit 1
    fi
    if ! aws s3 cp "$S3_PATH" - | tar -xzf - -P; then
        log_message "ERROR: Failed to download or extract backup from S3."
        exit 1
    fi
    log_message "Backup extracted."
    
    # CRITICAL STEP: Determine restore strategy (Initial Seed vs. Replace)
    local ORIGINAL_IP
    ORIGINAL_IP=$(echo "$MANIFEST_JSON" | jq -r '.source_node.ip_address')
    local IS_FIRST_NODE=
    local NODETOOL_HOSTS
    NODETOOL_HOSTS=$(echo "$LOADER_NODES" | sed 's/,/ -h /g')

    log_message "Determining restore strategy by checking seed nodes: $LOADER_NODES"
    if nodetool -h $NODETOOL_HOSTS status &>/dev/null; then
        IS_FIRST_NODE=false
        log_message "SUCCESS: Connected to live seed node. This node will join an existing cluster."
    else
        log_message "WARNING: Could not connect to any live seed nodes."
        log_message "This could be due to a network issue, or because this is the first node in a Disaster Recovery scenario."
        read -p "Do you want to proceed in 'FIRST NODE' mode (using initial_token)? Type 'yes' to confirm: " dr_confirmation
        if [[ "$dr_confirmation" != "yes" ]]; then
            log_message "Restore aborted by user. Please resolve seed node connectivity and re-run."
            exit 1
        fi
        IS_FIRST_NODE=true
    fi
    
    if [ "$IS_FIRST_NODE" = true ]; then
        log_message "Applying FIRST NODE strategy: Writing initial_token to cassandra.yaml"
        local TOKENS_FROM_BACKUP
        TOKENS_FROM_BACKUP=$(echo "$MANIFEST_JSON" | jq -r '.source_node.tokens | join(",")')
        local NUM_TOKENS
        NUM_TOKENS=$(echo "$MANIFEST_JSON" | jq -r '.source_node.tokens | length')

        if [ -z "$TOKENS_FROM_BACKUP" ] || [ "$NUM_TOKENS" -eq 0 ]; then
            log_message "ERROR: Cannot use initial_token strategy because token data is missing from backup manifest."
            exit 1
        fi

        echo "num_tokens: $NUM_TOKENS" >> "$CASSANDRA_YAML_FILE"
        echo "initial_token: '$TOKENS_FROM_BACKUP'" >> "$CASSANDRA_YAML_FILE"
        log_message "Successfully configured num_tokens and initial_token."

    else
        log_message "Applying SUBSEQUENT NODE strategy: Setting cassandra.replace_address_first_boot"
        if [ "$ORIGINAL_IP" == "$LISTEN_ADDRESS" ]; then
            log_message "INFO: Restoring to the same IP. No replacement necessary, but using this path for consistency."
        fi
        echo "-Dcassandra.replace_address_first_boot=$ORIGINAL_IP" >> "$JVM_OPTIONS_FILE"
        log_message "Successfully configured JVM for node replacement."
    fi

    log_message "5. Setting permissions..."
    chown -R $CASSANDRA_USER:$CASSANDRA_USER "$CASSANDRA_DATA_DIR"
    chown -R $CASSANDRA_USER:$CASSANDRA_USER "$CASSANDRA_COMMITLOG_DIR"
    chown -R $CASSANDRA_USER:$CASSANDRA_USER "$CASSANDRA_CACHES_DIR"
    log_message "Permissions set."

    log_message "6. Starting Cassandra service..."
    systemctl start cassandra
    log_message "Service started. Waiting for node to initialize..."

    local CASSANDRA_READY=false
    for i in {1..30}; do # Wait up to 5 minutes (30 * 10 seconds)
        if nodetool status > /dev/null 2>&1; then
            CASSANDRA_READY=true
            break
        fi
        log_message "Waiting for Cassandra to be ready... (attempt $i of 30)"
        sleep 10
    done

    # The trap will clean up configs automatically. We just need to report the final status.
    if [ "$CASSANDRA_READY" = true ]; then
        log_message "SUCCESS: Cassandra node is up and running."
        log_message "--- Full Restore Process Finished Successfully ---"
    else
        log_message "ERROR: Cassandra node failed to start within 5 minutes. Please check system logs for errors."
        log_message "Temporary restore flags have been automatically cleaned up."
        exit 1
    fi
}

# --- Function for Granular Restore using sstableloader ---
do_granular_restore() {
    local MANIFEST_JSON="$1"
    local restore_path
    local restore_type

    if [ -n "$TABLE_NAME" ]; then
        restore_type="Table '$TABLE_NAME' in Keyspace '$KEYSPACE_NAME'"
    else
        restore_type="Keyspace '$KEYSPACE_NAME'"
    fi

    log_message "--- Starting GRANULAR Restore for $restore_type from Backup ID: $BACKUP_ID ---"
    log_message "This will stream data into the LIVE cluster using sstableloader."

    local RESTORE_TEMP_DIR="/tmp/restore_$BACKUP_ID_$KEYSPACE_NAME"
    trap 'rm -rf "$RESTORE_TEMP_DIR"' EXIT
    
    log_message "Performing pre-restore disk space check for temporary directory /tmp..."
    if ! /usr/local/bin/disk-health-check.sh -p /tmp -c 15; then
        exit_code=${?}
        if [ $exit_code -eq 2 ]; then
            log_message "ERROR: CRITICAL lack of disk space in /tmp. Restore cannot proceed."
            log_message "Please free up space in /tmp and try again."
            exit 1
        fi
        log_message "WARNING: Disk space in /tmp is low. Continuing with restore, but monitor closely."
    fi
    log_message "Disk space check passed."

    mkdir -p "$RESTORE_TEMP_DIR"

    log_message "Downloading and extracting backup to temporary directory..."
    if [ "$BACKUP_BACKEND" != "s3" ]; then
        log_message "ERROR: Cannot restore from backend '$BACKUP_BACKEND'. This script only supports 's3'."
        exit 1
    fi
    aws s3 cp "$S3_PATH" - | tar -xzf - -C "$RESTORE_TEMP_DIR"
    
    # sstableloader needs the path to be .../keyspace/table/
    # The backup preserves the full path, so we can find it.
    local extracted_data_path="$RESTORE_TEMP_DIR$CASSANDRA_DATA_DIR"

    if [ -n "$TABLE_NAME" ]; then
        # Find the specific table directory (it has a UUID suffix)
        restore_path=$(find "$extracted_data_path/$KEYSPACE_NAME" -maxdepth 1 -type d -name "$TABLE_NAME-*")
        if [ -z "$restore_path" ] || [ ! -d "$restore_path" ]; then
            log_message "ERROR: Could not find table '$TABLE_NAME' in the backup for keyspace '$KEYSPACE_NAME'."
            exit 1
        fi
    else
        restore_path="$extracted_data_path/$KEYSPACE_NAME"
        if [ ! -d "$restore_path" ]; then
            log_message "ERROR: Could not find keyspace '$KEYSPACE_NAME' in the backup."
            exit 1
        fi
    fi

    log_message "Found data to restore at: $restore_path"
    log_message "Streaming data to cluster nodes ($LOADER_NODES) with sstableloader..."

    # Define SSL option based on cqlshrc
    local CQLSH_CONFIG="/root/.cassandra/cqlshrc"
    local CQLSH_SSL_OPT=""
    if [ -f "$CQLSH_CONFIG" ] && grep -q '\[ssl\]' "$CQLSH_CONFIG"; then
        log_message "INFO: SSL section found in cqlshrc, using --ssl for cqlsh commands."
        CQLSH_SSL_OPT="--ssl"
    fi

    # Ensure the schema exists before loading data
    log_message "Verifying schema exists..."
    if ! cqlsh ${CQLSH_SSL_OPT} -e "DESCRIBE KEYSPACE $KEYSPACE_NAME;" &>/dev/null; then
        log_message "ERROR: Keyspace '$KEYSPACE_NAME}' does not exist in the cluster."
        log_message "You must restore the schema before you can load data."
        log_message "Use the --schema-only flag to extract the schema from your backup:"
        log_message "  $0 --schema-only <backup_id>"
        log_message "Then apply it using: cqlsh ${CQLSH_SSL_OPT} -f /tmp/schema.cql"
        exit 1
    fi

    # Run the loader
    if sstableloader -d "$LOADER_NODES" "$restore_path"; then
        log_message "sstableloader completed successfully."
    else
        log_message "ERROR: sstableloader failed. Check its output above for details."
        exit 1
    fi

    log_message "Cleaning up temporary files..."
    rm -rf "$RESTORE_TEMP_DIR"
    trap - EXIT

    log_message "--- Granular Restore Process Finished Successfully ---"
}


# --- Main Logic: Argument Parsing ---

if [ "$#" -eq 0 ]; then
    usage
fi

if [ "$1" == "--schema-only" ]; then
    if [ -z "$2" ]; then
      log_message "ERROR: Backup ID must be provided after --schema-only flag."
      usage
    fi
    BACKUP_ID="$2"
    MODE="schema"
else
    BACKUP_ID="$1"
    KEYSPACE_NAME="$2"
    TABLE_NAME="$3"
    if [ -z "$BACKUP_ID" ]; then
        usage
    elif [ -z "$KEYSPACE_NAME" ]; then
        MODE="full"
    else
        MODE="granular"
    fi
fi


# --- Main Logic: Execution ---

# Determine backup type to find the right S3 path
BACKUP_TYPE=$(echo "$BACKUP_ID" | cut -d'_' -f1)
if [[ "$BACKUP_TYPE" != "full" && "$BACKUP_TYPE" != "incremental" ]]; then
    log_message "ERROR: Backup ID must start with 'full_' or 'incremental_'. Invalid ID: $BACKUP_ID"
    exit 1
fi

# Extract date from backup ID like 'type_YYYYMMDDHHMMSS'
BACKUP_DATE_STR=$(echo "$BACKUP_ID" | sed -n 's/.*_\([0-9]\{8\}\).*/\1/p')
if [ -z "$BACKUP_DATE_STR" ]; then
    log_message "ERROR: Could not extract date from backup ID '$BACKUP_ID'. Expected format: type_YYYYMMDDHHMMSS."
    exit 1
fi
BACKUP_DATE_FOLDER=$(date -d "$BACKUP_DATE_STR" '+%Y-%m-%d')


TARBALL_NAME="$HOSTNAME_$BACKUP_ID.tar.gz"
S3_PATH="s3://$S3_BUCKET_NAME/cassandra/$HOSTNAME/$BACKUP_DATE_FOLDER/$BACKUP_TYPE/$TARBALL_NAME"

log_message "Preparing to restore from S3 path: $S3_PATH"

# --- Fetch and verify manifest first ---
log_message "Fetching backup manifest for verification..."
if [ "$BACKUP_BACKEND" != "s3" ]; then
    log_message "ERROR: Cannot fetch manifest from backend '$BACKUP_BACKEND'. This script only supports 's3'."
    exit 1
fi
MANIFEST_JSON=$(aws s3 cp "$S3_PATH" - | tar -xzf - --to-stdout backup_manifest.json 2>/dev/null)

if [ -z "$MANIFEST_JSON" ]; then
    log_message "ERROR: Failed to fetch or find backup_manifest.json in the archive. The backup may be invalid or the S3 path incorrect."
    exit 1
fi

log_message "----------------- BACKUP MANIFEST -----------------"
echo "$MANIFEST_JSON" | jq '.' | tee -a "$RESTORE_LOG_FILE"
log_message "---------------------------------------------------"
read -p "Does the manifest above look correct? Type 'yes' to proceed: " manifest_confirmation
if [[ "$manifest_confirmation" != "yes" ]]; then
    log_message "Restore aborted by user based on manifest review."
    exit 0
fi

# --- Now, execute the chosen mode ---
case $MODE in
    "schema")
        do_schema_restore "$MANIFEST_JSON"
        ;;
    "full")
        do_full_restore "$MANIFEST_JSON"
        ;;
    "granular")
        do_granular_restore "$MANIFEST_JSON"
        ;;
    *)
        log_message "INTERNAL ERROR: Invalid mode detected."
        exit 1
        ;;
esac

exit 0
