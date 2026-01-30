#!/bin/bash
set -euo pipefail

# --- Defaults & Configuration ---
CONFIG_PATH="/etc/cassandra/conf/stress.conf"
# This is now a template file
PROFILE_TEMPLATE_PATH="/etc/cassandra/conf/stress-schema.yaml"
LOG_FILE="/var/log/cassandra/stress-test.log"

# --- Script Variables ---
WRITE_COUNT=""
READ_COUNT=""
NODES=""
AUTO_DETECTED_NODES=""
RF_STRING=""
# These will hold the final values to be used
EFFECTIVE_KEYSPACE="my_app"
EFFECTIVE_TABLE="users_large"
# These will hold the command-line overrides
KEYSPACE_OVERRIDE=""
TABLE_OVERRIDE=""

# --- Temp file for dynamic profile ---
TEMP_PROFILE_PATH=""
cleanup_temp_file() {
    if [[ -n "$TEMP_PROFILE_PATH" && -f "$TEMP_PROFILE_PATH" ]]; then
        rm -f "$TEMP_PROFILE_PATH"
    fi
}
trap cleanup_temp_file EXIT

# --- Logging ---
log_message() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# --- Usage ---
usage() {
    log_message "Usage: $0 [OPTIONS]"
    log_message "A robust wrapper for cassandra-stress using a YAML profile."
    log_message "This script will dynamically create the keyspace and table if they do not exist."
    log_message ""
    log_message "Operations (at least one is required):"
    log_message "  -w, --write <count>     Number of rows to write (e.g., 10M)."
    log_message "  -r, --read <count>      Number of rows to read."
    log_message ""
    log_message "Configuration:"
    log_message "  -n, --nodes <list>      Comma-separated list of node IPs. Default: auto-detect from 'nodetool status'."
    log_message "  --rf <strategy>         Set the replication factor. E.g., 'dc1:3,dc2:3' for NetworkTopologyStrategy."
    log_message "  -k, --keyspace <name>   Override the default keyspace ('my_app')."
    log_message "  -t, --table <table>     Override the default table ('users_large')."
    log_message "  -h, --help              Show this help message."
    exit 1
}

# --- Argument Parsing ---
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -w|--write) WRITE_COUNT="$2"; shift ;;
        -r|--read) READ_COUNT="$2"; shift ;;
        -n|--nodes) NODES="$2"; shift ;;
        --rf) RF_STRING="$2"; shift ;;
        -k|--keyspace) KEYSPACE_OVERRIDE="$2"; shift ;;
        -t|--table) TABLE_OVERRIDE="$2"; shift ;;
        -h|--help) usage ;;
        *) log_message "Unknown parameter passed: $1"; usage ;;
    esac
    shift
done

# --- Main Logic ---
log_message "--- Starting Cassandra Stress Test ---"

# 1. Validate Inputs
if [ -z "$WRITE_COUNT" ] && [ -z "$READ_COUNT" ]; then
    log_message "ERROR: You must specify at least one operation (-w or -r)."
    usage
fi

# 2. Source external config for credentials and SSL
if [ -f "$CONFIG_PATH" ]; then
    source "$CONFIG_PATH"
else
    log_message "WARNING: Config file not found at $CONFIG_PATH. Assuming no auth/ssl."
fi

# 3. Determine nodes to connect to
if [ -z "$NODES" ]; then
    log_message "Auto-detecting cluster nodes..."
    AUTO_DETECTED_NODES=$(nodetool status | grep '^UN' | awk '{print $2}' | tr '\n' ',' | sed 's/,$//')
    if [ -z "$AUTO_DETECTED_NODES" ]; then
        log_message "ERROR: Could not auto-detect any UP/NORMAL nodes."
        exit 1
    fi
    log_message "Found nodes: $AUTO_DETECTED_NODES"
    NODES="$AUTO_DETECTED_NODES"
fi

# 4. Generate the dynamic YAML profile
if [ -n "$KEYSPACE_OVERRIDE" ]; then
    EFFECTIVE_KEYSPACE="$KEYSPACE_OVERRIDE"
fi
if [ -n "$TABLE_OVERRIDE" ]; then
    EFFECTIVE_TABLE="$TABLE_OVERRIDE"
fi

# Construct replication strategy string
REPLICATION_STRATEGY=""
if [[ -n "$RF_STRING" ]]; then
    log_message "Using custom replication factor: $RF_STRING"
    MAP_PARTS=""
    IFS=',' read -ra DCRS <<< "$RF_STRING"
    for dc_rf in "${DCRS[@]}"; do
        DC=$(echo "$dc_rf" | cut -d':' -f1)
        RF=$(echo "$dc_rf" | cut -d':' -f2)
        if [ -z "$RF" ]; then # Handle single number for SimpleStrategy
            REPLICATION_STRATEGY="{'class': 'SimpleStrategy', 'replication_factor': ${DC}}"
            break
        fi
        if [[ -n "$MAP_PARTS" ]]; then
            MAP_PARTS+=", "
        fi
        MAP_PARTS+="'${DC}': ${RF}"
    done
    if [[ -z "$REPLICATION_STRATEGY" ]]; then
        REPLICATION_STRATEGY="{'class': 'NetworkTopologyStrategy', ${MAP_PARTS}}"
    fi
else
    log_message "Using default replication: SimpleStrategy, RF=1"
    REPLICATION_STRATEGY="{'class': 'SimpleStrategy', 'replication_factor': 1}"
fi

log_message "Using keyspace: '$EFFECTIVE_KEYSPACE' and table: '$EFFECTIVE_TABLE'"
TEMP_PROFILE_PATH=$(mktemp)
log_message "Generating temporary stress profile at $TEMP_PROFILE_PATH"

# Replace placeholders in the template. Use | as a delimiter for sed to avoid issues with JSON.
sed -e "s/my_app/$EFFECTIVE_KEYSPACE/g" \
    -e "s/users_large/$EFFECTIVE_TABLE/g" \
    -e "s|__REPLICATION_STRATEGY__|${REPLICATION_STRATEGY}|g" \
    "$PROFILE_TEMPLATE_PATH" > "$TEMP_PROFILE_PATH"


# --- Function to run a stress operation ---
run_stress() {
    local op_type="$1"
    local count="$2"
    local ops_string=""

    if [ "$op_type" == "write" ]; then
        ops_string="ops(insert=1)"
    elif [ "$op_type" == "read" ]; then
        # Note: The query name 'read_one' is hardcoded in the YAML, so we use it here.
        ops_string="ops(read_one=1)"
    else
        log_message "ERROR: Invalid operation type '$op_type'."
        return 1
    fi

    # Build the command array
    # The 'user' subcommand is required to use a YAML profile.
    local CMD_ARRAY=(
        "cassandra-stress"
        "user"
        "profile=$TEMP_PROFILE_PATH" # Use the dynamically generated profile
        "n=$count"
        "$ops_string"
        "-node" "$NODES"
    )

    if [ "${USE_SSL:-false}" = true ]; then
        CMD_ARRAY+=("-mode" "cql3" "native" "ssl")
    else
        CMD_ARRAY+=("-mode" "cql3" "native")
    fi

    # The user/password must be key=value, not flags, for the 'user' subcommand.
    if [ -n "${CASSANDRA_USER:-}" ]; then
        CMD_ARRAY+=("user=${CASSANDRA_USER}")
    fi
    
    if [ -n "${CASSANDRA_PASS:-}" ]; then
        CMD_ARRAY+=("password=${CASSANDRA_PASS}")
    fi
    
    log_message "Executing $op_type operation with count: $count"
    # Use printf for safe quoting of arguments
    log_message "Command: $(printf '%q ' "${CMD_ARRAY[@]}")"

    if ! "${CMD_ARRAY[@]}"; then
        local EXIT_CODE=$?
        log_message "ERROR: $op_type operation failed with exit code $EXIT_CODE."
        return $EXIT_CODE
    fi
    return 0
}

# 5. Execute Operations
if [ -n "$WRITE_COUNT" ]; then
    if ! run_stress "write" "$WRITE_COUNT"; then
        exit 1
    fi
fi

if [ -n "$READ_COUNT" ]; then
    if ! run_stress "read" "$READ_COUNT"; then
        exit 1
    fi
fi

log_message "--- Cassandra Stress Test Finished Successfully ---"
exit 0
