#!/bin/bash
# This file is managed by Puppet.
set -euo pipefail

# --- Defaults & Configuration ---
KEYSPACE="my_app"
TABLE="users_large"
PROFILE_PATH="/etc/cassandra/conf/stress-schema.yaml"
CONFIG_PATH="/etc/cassandra/conf/stress.conf"
NODES=""
WRITE_COUNT=""
READ_COUNT=""
DELETE_COUNT=""
LOG_FILE="/var/log/cassandra/stress-test.log"
NO_WARMUP=false

# Source credentials and SSL settings from config file if it exists
if [ -f "$CONFIG_PATH" ]; then
    source "$CONFIG_PATH"
fi

# --- Color Codes ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# --- Logging ---
log_message() {
    echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# --- Usage ---
usage() {
    log_message "${YELLOW}Usage: $0 [OPTIONS]${NC}"
    log_message "A robust wrapper for cassandra-stress."
    log_message "Credentials and SSL settings are automatically configured via $CONFIG_PATH."
    log_message ""
    log_message "Operations (at least one is required):"
    log_message "  -w, --write <count>     Number of rows to write (e.g., 10M for 10 million)."
    log_message "  -r, --read <count>      Number of rows to read. Use 'ALL' for a full read test."
    log_message "  -d, --delete <count>    Number of rows to delete."
    log_message ""
    log_message "Configuration:"
    log_message "  -k, --keyspace <name>   Keyspace to use. Default: $KEYSPACE"
    log_message "  -t, --table <table>     Table to use. Default: $TABLE"
    log_message "  -p, --profile <path>    Path to the stress profile YAML. Default: $PROFILE_PATH"
    log_message "  -n, --nodes <list>      Comma-separated list of node IPs. Default: auto-detect from nodetool."
    log_message "  --no-warmup             Skip the read phase before a write operation."
    log_message "  -h, --help              Show this help message."
    exit 1
}

# --- Argument Parsing ---
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -w|--write) WRITE_COUNT="$2"; shift ;;
        -r|--read) READ_COUNT="$2"; shift ;;
        -d|--delete) DELETE_COUNT="$2"; shift ;;
        -k|--keyspace) KEYSPACE="$2"; shift ;;
        -t|--table) TABLE="$2"; shift ;;
        -p|--profile) PROFILE_PATH="$2"; shift ;;
        -n|--nodes) NODES="$2"; shift ;;
        --no-warmup) NO_WARMUP=true ;;
        -h|--help) usage ;;
        *) log_message "${RED}Unknown parameter passed: $1${NC}"; usage ;;
    esac
    shift
done

# Validate that at least one operation is specified
if [ -z "$WRITE_COUNT" ] && [ -z "$READ_COUNT" ] && [ -z "$DELETE_COUNT" ]; then
    log_message "${RED}ERROR: You must specify at least one operation (-w, -r, or -d).${NC}"
    usage
fi

# --- Main Logic ---
log_message "${BLUE}--- Starting Cassandra Stress Test ---${NC}"

# Auto-detect nodes if not provided
if [ -z "$NODES" ]; then
    log_message "${BLUE}Auto-detecting cluster nodes...${NC}"
    NODES=$(nodetool status | grep '^UN' | awk '{print $2}' | tr '\n' ',' | sed 's/,$//')
    if [ -z "$NODES" ]; then
        log_message "${RED}ERROR: Could not auto-detect any UP/NORMAL nodes from 'nodetool status'.${NC}"
        exit 1
    fi
    log_message "${BLUE}Found nodes: $NODES${NC}"
fi

# Construct the base command
CMD_BASE="cassandra-stress"
CMD_ARGS=()

if [ -f "$PROFILE_PATH" ]; then
    CMD_ARGS+=("user" "profile=$PROFILE_PATH")
else
    log_message "${YELLOW}WARNING: Stress profile not found at $PROFILE_PATH. Relying on command-line schema.${NC}"
    CMD_ARGS+=("keyspace=$KEYSPACE" "table=$TABLE")
fi

CMD_ARGS+=("-node" "$NODES")

# Add authentication arguments if provided in config
if [ -n "${CASSANDRA_USER:-}" ]; then
    CMD_ARGS+=("-user" "$CASSANDRA_USER")
fi
if [ -n "${CASSANDRA_PASS:-}" ]; then
    CMD_ARGS+=("-password" "$CASSANDRA_PASS")
fi

# Add SSL mode if requested in config
if [ "${USE_SSL:-false}" = true ]; then
    CMD_ARGS+=("-mode" "ssl" "encryption=true")
fi


# Function to run a stress operation
run_stress() {
    local operation_type="$1"
    local operation_count="$2"
    
    local op_cmd_args=("${CMD_ARGS[@]}")
    op_cmd_args+=("$operation_type" "n=$operation_count")
    
    log_message "${BLUE}Executing $operation_type operation with count: $operation_count${NC}"
    log_message "Command: $CMD_BASE ${op_cmd_args[*]}"

    if "$CMD_BASE" "${op_cmd_args[@]}"; then
        log_message "${GREEN}--- $operation_type operation completed successfully. ---${NC}"
    else
        local exit_code=$?
        log_message "${RED}ERROR: $operation_type operation failed with exit code $exit_code.${NC}"
        exit $exit_code
    fi
}

# Execute operations in a safe order: write -> read -> delete
if [ -n "$WRITE_COUNT" ]; then
    if [ "$NO_WARMUP" = false ]; then
        log_message "${BLUE}Performing pre-write warmup read to populate caches...${NC}"
        run_stress "read" "100k" # A small, fixed read to warm up the system
    fi
    run_stress "write" "$WRITE_COUNT"
fi

if [ -n "$READ_COUNT" ]; then
    if [[ "$READ_COUNT" == "ALL" ]]; then
        log_message "${BLUE}Read set to ALL. This will read all previously written data.${NC}"
        # The 'n=' parameter for read defaults to all written data if not specified, 
        # but let's make it explicit for mixed workloads.
        read_op_count="${WRITE_COUNT:-10M}" # Default to a large number if no write was done
        run_stress "read" "$read_op_count"
    else
        run_stress "read" "$READ_COUNT"
    fi
fi

if [ -n "$DELETE_COUNT" ]; then
    run_stress "delete" "$DELETE_COUNT"
fi

log_message "${GREEN}--- Cassandra Stress Test Finished ---${NC}"
exit 0
