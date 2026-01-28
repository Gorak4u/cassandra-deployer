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
OPS_SPEC=""
PROFILE_PATH=""
NODE_LIST=""
CONSISTENCY_LEVEL="LOCAL_ONE"
TRUNCATE_STRATEGY="never"
PORT="9042"
DURATION=""
OP_COUNT=""

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
    log_message ""
    log_message "${BLUE}COMMANDS (choose one):${NC}"
    log_message "  -w, --write <count>      Run a simple write test (e.g., 10M)."
    log_message "  -r, --read <count>       Run a simple read test."
    log_message "  --mixed <ops_spec>       Run a mixed-ratio test (e.g., 'insert=1,read=2')."
    log_message "  --user <profile_path>    Run a test based on a user-defined YAML profile. Requires --ops."
    log_message ""
    log_message "${BLUE}OPTIONS:${NC}"
    log_message "  -n, --count <count>      Number of operations for mixed/user/write/read commands."
    log_message "  --duration <time>        Run for a specific duration (e.g., '30s', '10m'). Overrides -n."
    log_message "  --ops <ops_spec>         Operations spec for user/mixed mode (e.g., 'insert=1,read_one=1')."
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
            OP_COUNT="$2"
            shift ;;
        -r|--read)
            COMMAND="read"
            OP_COUNT="$2"
            shift ;;
        --mixed)
            COMMAND="mixed"
            OPS_SPEC="$2"
            shift ;;
        --user)
            COMMAND="user"
            PROFILE_PATH="$2"
            shift ;;
        -n|--count)
            OP_COUNT="$2"
            shift ;;
        --duration)
            DURATION="$2"
            shift ;;
        --ops)
            OPS_SPEC="$2"
            shift ;;
        --nodes)
            NODE_LIST="$2"
            shift ;;
        --cl)
            CONSISTENCY_LEVEL="$2"
            shift ;;
        --truncate)
            TRUNCATE_STRATEGY="$2"
            shift ;;
        --port)
            PORT="$2"
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
    log_message "${RED}ERROR: You must specify a command (-w, -r, --user, etc.).${NC}"
    usage
fi

# For simple write/read commands, set the ops spec automatically
if [[ "$COMMAND" == "write" && -z "$OPS_SPEC" ]]; then
    OPS_SPEC="insert=1"
fi
if [[ "$COMMAND" == "read" && -z "$OPS_SPEC" ]]; then
    OPS_SPEC="read=1"
fi


log_message "${BLUE}--- Preparing Cassandra Stress Test (Command: $COMMAND) ---${NC}"

# Source credentials and SSL settings from config file if it exists
if [ -f "$CONFIG_PATH" ]; then
    source "$CONFIG_PATH"
fi

# Auto-detect nodes if not provided
if [ -z "$NODE_LIST" ]; then
    log_message "${BLUE}Auto-detecting cluster nodes...${NC}"
    NODE_LIST=$(nodetool status 2>/dev/null | grep '^UN' | awk '{print $2}' | tr '\n' ',' | sed 's/,$//')
    if [ -z "$NODE_LIST" ]; then
        log_message "${RED}ERROR: Could not auto-detect any UP/NORMAL nodes.${NC}"
        exit 1
    fi
    log_message "${BLUE}Found nodes: $NODE_LIST${NC}"
fi

# Build Command-Specific Options (these are key=value pairs)
declare -a CMD_OPTS
if [ -n "$OP_COUNT" ]; then CMD_OPTS+=("n=$OP_COUNT"); fi
if [ -n "$DURATION" ]; then CMD_OPTS+=("duration=$DURATION"); fi
if [ -n "$OPS_SPEC" ]; then CMD_OPTS+=("ops($OPS_SPEC)"); fi
if [ -n "$PROFILE_PATH" ]; then CMD_OPTS+=("profile=$PROFILE_PATH"); fi
CMD_OPTS+=("cl=$CONSISTENCY_LEVEL")
CMD_OPTS+=("truncate=$TRUNCATE_STRATEGY")

# Build Global Options (prefixed with -)
declare -a GLOBAL_OPTS
GLOBAL_OPTS+=("-node" "$NODE_LIST")
GLOBAL_OPTS+=("-port" "$PORT")

# Build the -mode option string correctly
declare -a MODE_PARTS=("native" "cql3")
if [ -n "${CASSANDRA_USER:-}" ]; then MODE_PARTS+=("user=${CASSANDRA_USER}"); fi
if [ -n "${CASSANDRA_PASS:-}" ]; then MODE_PARTS+=("password=${CASSANDRA_PASS}"); fi
if [ "${USE_SSL:-false}" = true ]; then MODE_PARTS+=("ssl"); fi

# Join the parts into a single string for the -mode argument
MODE_STRING=$(IFS=' '; echo "${MODE_PARTS[*]}")
GLOBAL_OPTS+=("-mode" "$MODE_STRING")


# Build the final command array in the correct order
# cassandra-stress [global-opts] <command> [command-opts]
FINAL_CMD=("cassandra-stress")
FINAL_CMD+=("${GLOBAL_OPTS[@]}")
FINAL_CMD+=("$COMMAND")
FINAL_CMD+=("${CMD_OPTS[@]}")

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
