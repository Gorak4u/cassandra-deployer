#!/bin/bash
# This file is managed by Puppet.
# A wrapper script to run a command on all nodes in the Cassandra cluster.

set -euo pipefail

# --- Color Codes ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# --- Defaults ---
MODE="sequential" # 'sequential' or 'parallel'
COMMAND_TO_RUN=""
DATACENTER=""
SSH_USER="root" # Assume root for sudo commands

# --- Logging ---
log_message() {
    echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# --- Usage ---
usage() {
    log_message "${YELLOW}Usage: $0 [OPTIONS] -- <command_to_run>${NC}"
    log_message "Runs a specified command on all nodes in the Cassandra cluster via SSH."
    log_message ""
    log_message "Options:"
    log_message "  --parallel          Run the command on all nodes simultaneously. Default is sequential."
    log_message "  --sequential        Run the command on one node at a time, waiting for completion before starting the next."
    log_message "  --dc <datacenter>   Only run on nodes in the specified datacenter."
    log_message "  --user <user>       The user to SSH as. Default: 'root'."
    log_message "  -h, --help          Show this help message."
    log_message ""
    log_message "Example (run repair sequentially across the cluster):"
    log_message "  $0 --sequential -- cass-ops repair"
    log_message ""
    log_message "Example (check health on all nodes in parallel):"
    log_message "  $0 --parallel -- cass-ops health"
    log_message ""
    log_message "Example (run on a specific DC):"
    log_message "  $0 --dc us-east-1 -- cass-ops cleanup"
    exit 1
}

# --- Argument Parsing ---
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --parallel) MODE="parallel"; shift ;;
        --sequential) MODE="sequential"; shift ;;
        --dc) DATACENTER="$2"; shift 2 ;;
        --user) SSH_USER="$2"; shift 2 ;;
        -h|--help) usage ;;
        --) shift; COMMAND_TO_RUN="$@"; break ;;
        *) log_message "${RED}Unknown option: $1${NC}"; usage ;;
    esac
done

if [ -z "$COMMAND_TO_RUN" ]; then
    log_message "${RED}ERROR: No command specified to run on cluster nodes.${NC}"
    usage
fi

# --- Main Logic ---
log_message "${BLUE}--- Starting Cluster-Wide Command Execution ---${NC}"
log_message "Mode: ${BOLD}$MODE${NC}"
if [ -n "$DATACENTER" ]; then
    log_message "Target Datacenter: ${BOLD}$DATACENTER${NC}"
fi
log_message "Command: ${BOLD}$COMMAND_TO_RUN${NC}"

# Get list of nodes from nodetool status
log_message "Fetching node list from cluster..."
NODETOOL_STATUS_OUTPUT=$(nodetool status 2>/dev/null)
if [ -z "$NODETOOL_STATUS_OUTPUT" ]; then
    log_message "${RED}ERROR: Failed to run 'nodetool status'. Cannot determine cluster nodes.${NC}"
    exit 1
fi

NODE_LIST=()
while IFS= read -r line; do
    # Skip headers and blank lines
    if [[ ! "$line" =~ ^[UD][NLJM] ]]; then
        continue
    fi
    
    node_dc=$(echo "$line" | awk '{print $4}')
    # Filter by DC if specified
    if [ -n "$DATACENTER" ] && [ "$node_dc" != "$DATACENTER" ]; then
        continue
    fi
    
    NODE_LIST+=("$(echo "$line" | awk '{print $2}')")

done <<< "$NODETOOL_STATUS_OUTPUT"

if [ ${#NODE_LIST[@]} -eq 0 ]; then
    log_message "${RED}ERROR: No nodes found in the cluster (or matching the specified DC).${NC}"
    exit 1
fi

log_message "Found ${#NODE_LIST[@]} nodes to run command on:"
printf " - %s\n" "${NODE_LIST[@]}"

# --- Command Execution ---
if [ "$MODE" == "sequential" ]; then
    log_message "${BLUE}--- Executing Sequentially ---${NC}"
    for node in "${NODE_LIST[@]}"; do
        log_message "--- Running on node: ${BOLD}$node${NC} ---"
        if ! ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 "$SSH_USER@$node" "$COMMAND_TO_RUN"; then
            log_message "${RED}ERROR: Command failed on node $node. Aborting sequential execution.${NC}"
            exit 1
        fi
        log_message "--- Completed on node: ${BOLD}$node${NC} ---"
    done
    log_message "${GREEN}Sequential execution completed successfully on all nodes.${NC}"
else # Parallel
    log_message "${BLUE}--- Executing in Parallel ---${NC}"
    PIDS=()
    FAILURES=0
    for node in "${NODE_LIST[@]}"; do
        # Run in background
        ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 "$SSH_USER@$node" "$COMMAND_TO_RUN" &
        PIDS+=($!)
    done

    # Wait for all background jobs to finish
    for pid in "${PIDS[@]}"; do
        if ! wait "$pid"; then
            ((FAILURES++))
        fi
    done

    if [ "$FAILURES" -gt 0 ]; then
        log_message "${RED}Parallel execution finished with $FAILURES failure(s).${NC}"
        exit 1
    else
        log_message "${GREEN}Parallel execution completed successfully on all nodes.${NC}"
    fi
fi

exit 0
