#!/bin/bash
# This file is managed by Puppet.
set -euo pipefail

# --- Defaults & Configuration ---
KEYSPACE="my_app"
TABLE="users_large"
PROFILE_PATH="/etc/cassandra/conf/stress-schema.yaml"
CONFIG_PATH="/etc/cassandra/conf/stress.conf"
NODES=""
OPS_SPEC="" # New: for custom ops ratios
DURATION="" # New: for time-based runs
WRITE_COUNT=""
READ_COUNT=""
DELETE_COUNT=""
LOG_FILE="/var/log/cassandra/stress-test.log"
NO_WARMUP=false
CL="LOCAL_ONE"
TRUNCATE="never"

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
    log_message "Operations (at least one operation type is required):"
    log_message "  -w, --write <count>      Number of rows to write (e.g., 10M for 10 million). Shortcut for --ops 'write=1' -n <count>."
    log_message "  -r, --read <count>       Number of rows to read. Shortcut for --ops 'read=1' -n <count>."
    log_message "  -d, --delete <count>     Number of rows to delete. Shortcut for --ops 'delete=1' -n <count>."
    log_message "  --ops <spec>             Advanced: Specify custom operation ratios, e.g., 'write=2,read=1'."
    log_message "  -n, --count <count>      Number of operations to perform when using --ops."
    log_message "  --duration <time>        Time to run (e.g., '30s', '10m', '1h'). Overrides operation counts."
    log_message ""
    log_message "Configuration:"
    log_message "  -p, --profile <path>     Path to the stress profile YAML. Default: $PROFILE_PATH"
    log_message "  --nodes <list>           Comma-separated list of node IPs. Default: auto-detect from nodetool."
    log_message "  --cl <level>             Consistency Level to use. Default: $CL"
    log_message "  --truncate <when>        Truncate the table: never, before, or each. Default: $TRUNCATE"
    log_message "  --no-warmup              Skip the read phase before a write operation."
    log_message "  -h, --help               Show this help message."
    exit 1
}

# --- Argument Parsing ---
# Using a temporary variable for -n/--count because it's used with --ops
OP_COUNT=""
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -w|--write) WRITE_COUNT="$2"; shift ;;
        -r|--read) READ_COUNT="$2"; shift ;;
        -d|--delete) DELETE_COUNT="$2"; shift ;;
        --ops) OPS_SPEC="$2"; shift ;;
        -n|--count) OP_COUNT="$2"; shift ;;
        --duration) DURATION="$2"; shift ;;
        -p|--profile) PROFILE_PATH="$2"; shift ;;
        --nodes) NODES="$2"; shift ;;
        --cl) CL="$2"; shift ;;
        --truncate) TRUNCATE="$2"; shift ;;
        --no-warmup) NO_WARMUP=true ;;
        -h|--help) usage ;;
        *) log_message "${RED}Unknown parameter passed: $1${NC}"; usage ;;
    esac
    shift
done

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

# Check if profile exists
if [ ! -f "$PROFILE_PATH" ]; then
    log_message "${RED}ERROR: Stress profile not found at $PROFILE_PATH. This wrapper requires a profile.${NC}"
    exit 1
fi

CMD_BASE="cassandra-stress"

# --- Function to run a stress operation ---
run_stress() {
    local op_spec="$1"   # e.g., "write=1" or "write=2,read=1"
    local count_spec="$2" # e.g., "n=10M" or "duration=30s"

    # Start with base command
    local cmd_array=("$CMD_BASE")

    # Add global options (with dashes) FIRST
    cmd_array+=("-node" "$NODES")
    if [ -n "${CASSANDRA_USER:-}" ]; then cmd_array+=("-user" "$CASSANDRA_USER"); fi
    if [ -n "${CASSANDRA_PASS:-}" ]; then cmd_array+=("-password" "$CASSANDRA_PASS"); fi
    if [ "${USE_SSL:-false}" = true ]; then cmd_array+=("-mode" "ssl" "encryption=true"); fi
    
    # Now, add the subcommand and its key=value arguments
    cmd_array+=("user")
    cmd_array+=("profile=$PROFILE_PATH")
    cmd_array+=("ops($op_spec)")
    if [ -n "$count_spec" ]; then
        cmd_array+=("$count_spec")
    fi
    cmd_array+=("cl=$CL")
    cmd_array+=("truncate=$TRUNCATE")

    log_message "${BLUE}Executing stress operation...${NC}"
    # Use "${cmd_array[@]}" to handle arguments with spaces correctly
    log_message "Command: ${cmd_array[*]}"

    if "${cmd_array[@]}"; then
        log_message "${GREEN}--- Operation completed successfully. ---${NC}"
        return 0
    else
        local exit_code=$?
        log_message "${RED}ERROR: Stress operation failed with exit code $exit_code.${NC}"
        return $exit_code
    fi
}

# --- Determine which operations to run ---

# Handle complex --ops first
if [ -n "$OPS_SPEC" ]; then
    if [ -z "$OP_COUNT" ] && [ -z "$DURATION" ]; then
        log_message "${RED}ERROR: When using --ops, you must also specify --count or --duration.${NC}"
        usage
    fi
    
    count_arg=""
    if [ -n "$DURATION" ]; then
        count_arg="duration=$DURATION"
    elif [ -n "$OP_COUNT" ]; then
        count_arg="n=$OP_COUNT"
    fi
    
    run_stress "$OPS_SPEC" "$count_arg"

# Handle simple -w, -r, -d flags
else
    # Validate that at least one operation is specified
    if [ -z "$WRITE_COUNT" ] && [ -z "$READ_COUNT" ] && [ -z "$DELETE_COUNT" ]; then
        log_message "${RED}ERROR: You must specify at least one operation (-w, -r, -d) or use --ops.${NC}"
        usage
    fi

    # Execute operations in a safe order: write -> read -> delete
    if [ -n "$WRITE_COUNT" ]; then
        if [ "$NO_WARMUP" = false ]; then
            log_message "${BLUE}Performing pre-write warmup read to populate caches...${NC}"
            # This uses the new run_stress function correctly
            run_stress "read=1" "n=100k" || log_message "${YELLOW}Warmup read failed, continuing with write anyway.${NC}"
        fi
        run_stress "write=1" "n=$WRITE_COUNT" || exit 1
    fi

    if [ -n "$READ_COUNT" ]; then
        if [[ "$READ_COUNT" == "ALL" ]]; then
            log_message "${BLUE}Read set to ALL. This will read all previously written data.${NC}"
            read_op_count="${WRITE_COUNT:-10M}" # Default to a large number if no write was done
            run_stress "read=1" "n=$read_op_count" || exit 1
        else
            run_stress "read=1" "n=$READ_COUNT" || exit 1
        fi
    fi

    if [ -n "$DELETE_COUNT" ]; then
        run_stress "delete=1" "n=$DELETE_COUNT" || exit 1
    fi
fi

log_message "${GREEN}--- Cassandra Stress Test Finished ---${NC}"
exit 0
