#!/bin/bash
# This file is managed by Puppet.
# Checks Cassandra cluster health, Cqlsh connectivity, and native transport port

# --- Default Configuration ---
IP_ADDRESS=""
SILENT=false

# --- Color Codes ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

usage() {
    echo "Usage: $0 [OPTIONS] [ip_address]"
    echo "  Checks Cassandra cluster health."
    echo ""
    echo "Options:"
    echo "  -s, --silent      Enable silent mode. Only prints a final status message on failure."
    echo "  -h, --help        Show this help message."
    exit 1
}

# --- Argument Parsing ---
# Manual loop to handle flags and optional positional argument
args=()
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -s|--silent) SILENT=true; shift ;;
        -h|--help) usage ;;
        -*) echo "Unknown option: $1"; usage ;;
        *) args+=("$1"); shift ;;
    esac
done
# Restore positional arguments
set -- "${args[@]}"
if [ -n "$1" ]; then
    IP_ADDRESS="$1"
fi

# If IP_ADDRESS is still empty, get the default
if [ -z "$IP_ADDRESS" ]; then
    IP_ADDRESS=$(hostname -I | awk '{print $1}')
fi

# --- Logging ---
log_message() {
  if [ "$SILENT" = false ]; then
    echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
  fi
}

# --- Main Check Logic ---
FAILURE_REASON=""

run_checks() {
    local CQLSH_CONFIG="/root/.cassandra/cqlshrc"
    local CQLSH_SSL_OPT=""

    # Check for SSL configuration in cqlshrc
    if [ -f "$CQLSH_CONFIG" ] && grep -q '\[ssl\]' "$CQLSH_CONFIG"; then
        log_message "${BLUE}SSL section found in cqlshrc, using --ssl for cqlsh commands.${NC}"
        CQLSH_SSL_OPT="--ssl"
    fi

    # 1. Check nodetool status for 'UN' (Up, Normal) on ALL nodes
    log_message "${BLUE}Checking that all nodes are Up/Normal...${NC}"
    NODETOOL_STATUS=$(nodetool status 2>&1)
    
    # Check for nodetool command failure first
    if [ $? -ne 0 ]; then
        log_message "${RED}Nodetool status command failed to execute.${NC}"
        if [ "$SILENT" = false ]; then
            echo "$NODETOOL_STATUS"
        fi
        FAILURE_REASON="Nodetool command failed"
        return 1
    fi

    # Grep for any nodes that are NOT Up/Normal (UN). This includes DN, UJ, UL, etc.
    # Exclude header and blank lines.
    NON_UN_NODES=$(echo "$NODETOOL_STATUS" | tail -n +6 | head -n -1 | grep -Ev '^(UN|Address)' | grep -v '^\s*$' || true)
    
    if [ -n "$NON_UN_NODES" ]; then
        log_message "${RED}Nodetool status: FAILED - Not all nodes are in UN state.${NC}"
        if [ "$SILENT" = false ]; then
            echo "The following nodes are not Up/Normal:"
            echo "$NON_UN_NODES"
        fi
        local first_bad_node_info
        first_bad_node_info=$(echo "$NON_UN_NODES" | head -n 1 | awk '{print $2 " is " $1}')
        FAILURE_REASON="One or more nodes are not Up/Normal (e.g., $first_bad_node_info)"
        return 1
    else
        log_message "${GREEN}Nodetool status: OK - All nodes are Up/Normal.${NC}"
    fi

    # 2. Check cqlsh connectivity
    log_message "${BLUE}Checking cqlsh connectivity using $CQLSH_CONFIG...${NC}"
    if ! cqlsh --cqlshrc "$CQLSH_CONFIG" ${CQLSH_SSL_OPT} "${IP_ADDRESS}" -e "SELECT cluster_name FROM system.local;" >/dev/null 2>&1; then
      log_message "${RED}Cqlsh connectivity: FAILED${NC}"
      FAILURE_REASON="Cqlsh connectivity failed"
      return 1
    fi
    log_message "${GREEN}Cqlsh connectivity: OK${NC}"


    # 3. Check native transport port 9042 using nc
    log_message "${BLUE}Checking native transport port 9042...${NC}"
    if ! nc -z -w 5 "${IP_ADDRESS}" 9042 >/dev/null 2>&1; then
      log_message "${RED}Port 9042 (Native Transport): CLOSED or FAILED${NC}"
      FAILURE_REASON="Port 9042 (Native Transport) is closed"
      return 1
    fi
    log_message "${GREEN}Port 9042 (Native Transport): OPEN${NC}"

    return 0
}


# --- Execution ---
if run_checks; then
    log_message "${GREEN}Cluster health check completed successfully.${NC}"
    exit 0
else
    if [ "$SILENT" = true ]; then
        # Print only the failure reason to stderr for scripting
        echo -e "${RED}FAILED: $FAILURE_REASON${NC}" >&2
    else
        # The detailed error is already logged by `log_message` in non-silent mode.
        log_message "${RED}Cluster health check FAILED.${NC}"
    fi
    exit 1
fi
