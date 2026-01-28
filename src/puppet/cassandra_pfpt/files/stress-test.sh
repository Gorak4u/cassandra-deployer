#!/bin/bash
# This file is managed by Puppet.
# A wrapper for the cassandra-stress tool, designed from scratch to provide a
# user-friendly interface for common stress testing commands.
set -euo pipefail

# --- Defaults & Configuration ---
CONFIG_PATH="/etc/cassandra/conf/stress.conf"
LOG_FILE="/var/log/cassandra/stress-test.log"

# Script options
COMMAND=""
COMMAND_ARGS=()
COMMON_OPTS=()
GLOBAL_OPTS=()

# --- Color Codes & Logging ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_message() {
    echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# --- Usage ---
usage() {
    log_message "${YELLOW}Usage: $0 <command> [options]${NC}"
    log_message ""
    log_message "${BLUE}DESCRIPTION:${NC}"
    log_message "  A user-friendly wrapper for the 'cassandra-stress' utility."
    log_message "  This script simplifies common testing scenarios by mapping flags to the correct"
    log_message "  'cassandra-stress' subcommands and arguments."
    log_message ""
    log_message "${BLUE}COMMANDS (choose one):${NC}"
    log_message "  -w, --write <count>      Run a simple write test for a number of operations (e.g., 10M)."
    log_message "  -r, --read <count>       Run a simple read test."
    log_message "  --counter-write <count>  Run a simple counter write test."
    log_message "  --counter-read <count>   Run a simple counter read test."
    log_message "  --mixed <ops_spec>     Run a mixed-ratio test (e.g., --mixed 'insert=1,read1=2'). Requires -n or --duration."
    log_message "  --user <profile_path>  Run a test based on a user-defined YAML profile. Requires an ops spec."
    log_message ""
    log_message "${BLUE}OPTIONS:${NC}"
    log_message "  -n, --count <count>      Number of operations to perform for mixed/user commands."
    log_message "  --duration <time>        Run for a specific duration (e.g., '30s', '10m'). Overrides -n."
    log_message "  --ops <ops_spec>         Operations spec for user/mixed mode (e.g., 'read_one=1')."
    log_message "  --nodes <list>           Comma-separated list of nodes (default: auto-detect)."
    log_message "  --cl <level>             Consistency Level to use (default: LOCAL_ONE)."
    log_message "  --truncate <when>        Truncate table: 'never', 'before', or 'each' (default: never)."
    log_message "  --port <port>            The CQL native port (default: 9042)."
    log_message "  -h, --help               Show this help message."
    exit 1
}

# --- Argument Parsing ---
if [ "$#" -eq 0 ]; then
    usage
fi

while [[ "$#" -gt 0 ]]; do
    case $1 in
        -w|--write)
            COMMAND="write"
            COMMAND_ARGS+=("n=$2")
            shift ;;
        -r|--read)
            COMMAND="read"
            COMMAND_ARGS+=("n=$2")
            shift ;;
        --counter-write)
            COMMAND="counter_write"
            COMMAND_ARGS+=("n=$2")
            shift ;;
        --counter-read)
            COMMAND="counter_read"
            COMMAND_ARGS+=("n=$2")
            shift ;;
        --mixed)
            COMMAND="mixed"
            COMMAND_ARGS+=("ops($2)")
            shift ;;
        --user)
            COMMAND="user"
            COMMAND_ARGS+=("profile=$2")
            shift ;;
        -n|--count)
            COMMAND_ARGS+=("n=$2")
            shift ;;
        --duration)
            # Remove any previous n= args and add duration
            COMMAND_ARGS=("${COMMAND_ARGS[@]/n=*}")
            COMMAND_ARGS+=("duration=$2")
            shift ;;
        --ops)
            COMMAND_ARGS+=("ops($2)")
            shift ;;
        --nodes)
            GLOBAL_OPTS+=("-node" "$2")
            shift ;;
        --cl)
            COMMON_OPTS+=("cl=$2")
            shift ;;
        --truncate)
            COMMON_OPTS+=("truncate=$2")
            shift ;;
        --port)
            GLOBAL_OPTS+=("-port" "$2")
            shift ;;
        -h|--help)
            usage ;;
        *)
            log_message "${RED}Unknown parameter passed: $1${NC}"
            usage ;;
    esac
    shift
done

# --- Main Logic ---

# Validate a command was chosen
if [ -z "$COMMAND" ]; then
    log_message "${RED}ERROR: You must specify a command (-w, -r, --mixed, etc.).${NC}"
    usage
fi

log_message "${BLUE}--- Preparing Cassandra Stress Test (Command: $COMMAND) ---${NC}"

# Source credentials and SSL settings from config file if it exists
if [ -f "$CONFIG_PATH" ]; then
    source "$CONFIG_PATH"
fi

# Add auth options if present in the config file
if [ -n "${CASSANDRA_USER:-}" ]; then GLOBAL_OPTS+=("-user" "$CASSANDRA_USER"); fi
if [ -n "${CASSANDRA_PASS:-}" ]; then GLOBAL_OPTS+=("-password" "$CASSANDRA_PASS"); fi
if [ "${USE_SSL:-false}" = true ]; then GLOBAL_OPTS+=("-mode" "ssl"); fi

# Auto-detect nodes if not provided via --nodes flag
# Check if -node is already in GLOBAL_OPTS
if ! [[ " ${GLOBAL_OPTS[*]} " =~ " -node " ]]; then
    log_message "${BLUE}Auto-detecting cluster nodes...${NC}"
    NODES=$(nodetool status 2>/dev/null | grep '^UN' | awk '{print $2}' | tr '\n' ',' | sed 's/,$//')
    if [ -z "$NODES" ]; then
        log_message "${RED}ERROR: Could not auto-detect any UP/NORMAL nodes from 'nodetool status'.${NC}"
        log_message "${YELLOW}Please specify nodes manually with the --nodes flag.${NC}"
        exit 1
    fi
    log_message "${BLUE}Found nodes: $NODES${NC}"
    GLOBAL_OPTS+=("-node" "$NODES")
fi

# Set defaults for common options if not provided
if ! [[ " ${COMMON_OPTS[*]} " =~ "cl=" ]]; then COMMON_OPTS+=("cl=$CL"); fi
if ! [[ " ${COMMON_OPTS[*]} " =~ "truncate=" ]]; then COMMON_OPTS+=("truncate=$TRUNCATE"); fi
if ! [[ " ${GLOBAL_OPTS[*]} " =~ " -port " ]]; then GLOBAL_OPTS+=("-port" "$PORT"); fi


# Build the final command
# Correct order: cassandra-stress [global opts] <command> [command opts]
FINAL_CMD=("cassandra-stress")
FINAL_CMD+=("${GLOBAL_OPTS[@]}")
FINAL_CMD+=("$COMMAND")
FINAL_CMD+=("${COMMAND_ARGS[@]}")
FINAL_CMD+=("${COMMON_OPTS[@]}")

log_message "${BLUE}Executing stress command...${NC}"
log_message "Full command: ${FINAL_CMD[*]}"

# Execute the command
if "${FINAL_CMD[@]}"; then
    log_message "${GREEN}--- Stress test completed successfully. ---${NC}"
    exit 0
else
    EXIT_CODE=$?
    log_message "${RED}ERROR: Stress test command failed with exit code $EXIT_CODE.${NC}"
    exit $EXIT_CODE
fi
