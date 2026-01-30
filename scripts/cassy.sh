#!/bin/bash
#
# A wrapper script to execute commands or scripts on multiple remote nodes via SSH.
# This script is intended to be run from an external management server (e.g., Jenkins).

set -euo pipefail

# --- Defaults ---
SSH_USER=""
SSH_OPTIONS=""
NODES=()
COMMAND=""
SCRIPT_PATH=""
PARALLEL=false
QV_QUERY=""

# --- Color Codes ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# --- Logging ---
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# --- Usage ---
usage() {
    cat <<EOF
${BOLD}Cluster Orchestration Tool${NC}

A wrapper to execute commands or scripts on multiple remote nodes via SSH.
Supports both static node lists and dynamic inventory fetching via the 'qv' tool.

${YELLOW}Usage:${NC}
  $0 [OPTIONS]

${YELLOW}Node Selection (choose one method):${NC}
  -n, --nodes <list>        A comma-separated list of target node hostnames or IPs.
  -f, --nodes-file <path>   A file containing a list of target nodes, one per line.
  --node <host>             Specify a single target node.
  --qv-query "<query>"      A quoted string of 'qv' flags to dynamically fetch a node list.

${YELLOW}Action (choose one):${NC}
  -c, --command <command>   The shell command to execute on each node.
  -s, --script <path>       The path to a local script to copy and execute on each node.

${YELLOW}Execution Options:${NC}
  -l, --user <user>         The SSH user to connect as. Defaults to the current user.
  -P, --parallel            Execute on all nodes in parallel instead of sequentially.
  --ssh-options <opts>      Quoted string of additional options for the SSH command (e.g., "-i /path/key.pem").

  -h, --help                Show this help message.

${YELLOW}Examples:${NC}
  ${GREEN}# Run a health check on all nodes sequentially:${NC}
  $0 -n "node1,node2,node3" -c "sudo cass-ops health"

  ${GREEN}# Dynamically get all Cassandra nodes in the SC4 datacenter and run a repair in parallel:${NC}
  $0 --qv-query "-r role_cassandra -d SC4" -P -c "sudo cass-ops repair"

  ${GREEN}# Execute a local script on a single node as the 'admin' user:${NC}
  $0 --node node1 -l admin -s ./local_script.sh
EOF
    exit 1
}

# --- Argument Parsing ---
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -n|--nodes) IFS=',' read -r -a NODES <<< "$2"; shift ;;
        -f|--nodes-file)
            if [ ! -f "$2" ]; then log_error "Node file not found: $2"; exit 1; fi
            mapfile -t NODES < "$2"
            shift ;;
        --node) NODES=("$2"); shift ;;
        --qv-query) QV_QUERY="$2"; shift ;;
        -c|--command) COMMAND="$2"; shift ;;
        -s|--script) SCRIPT_PATH="$2"; shift ;;
        -l|--user) SSH_USER="$2"; shift ;;
        -P|--parallel) PARALLEL=true ;;
        --ssh-options) SSH_OPTIONS="$2"; shift ;;
        -h|--help) usage ;;
        *) log_error "Unknown parameter passed: $1"; usage ;;
    esac
    shift
done

# --- Validation ---
if [ ${#NODES[@]} -eq 0 ] && [ -z "$QV_QUERY" ]; then
    log_error "No target nodes specified. Use --nodes, --nodes-file, --node, or --qv-query."
    usage
fi
if [ -n "$QV_QUERY" ] && [ ${#NODES[@]} -gt 0 ]; then
    log_error "Specify either a static node source (--nodes, etc.) or --qv-query, but not both."
    usage
fi
if [ -z "$COMMAND" ] && [ -z "$SCRIPT_PATH" ]; then
    log_error "No action specified. Use --command or --script."
    usage
fi
if [ -n "$COMMAND" ] && [ -n "$SCRIPT_PATH" ]; then
    log_error "Specify either --command or --script, but not both."
    usage
fi
if [ -n "$SCRIPT_PATH" ] && [ ! -f "$SCRIPT_PATH" ]; then
    log_error "Script file not found: $SCRIPT_PATH"
    exit 1
fi

# --- Node Discovery ---
if [ -n "$QV_QUERY" ]; then
    log_info "Fetching node list from inventory tool (qv)..."
    if ! command -v qv &> /dev/null; then
        log_error "'qv' command not found. Cannot fetch inventory."
        exit 1
    fi
    
    # Use process substitution and mapfile to read nodes into an array.
    # The '-t' flag provides one FQDN per line, which is ideal for this.
    # The eval is used to correctly handle the quoted query string with its spaces.
    log_info "Running query: qv -t ${QV_QUERY}"
    mapfile -t NODES < <(eval "qv -t $QV_QUERY" 2>/dev/null)

    if [ ${#NODES[@]} -eq 0 ]; then
        log_error "The qv query returned no hosts. Aborting."
        exit 1
    fi
fi

# --- Execution ---
log_info "Target nodes: ${NODES[*]}"
PARALLEL_MODE=$(if [ "$PARALLEL" = true ]; then echo "Parallel"; else echo "Sequential"; fi)
log_info "Execution mode: ${PARALLEL_MODE}"
log_info "SSH user: ${SSH_USER:-$(whoami)}"

pids=()
failed_nodes=()

# Prepare SSH user argument
SSH_USER_ARG=""
if [ -n "$SSH_USER" ]; then
    SSH_USER_ARG="${SSH_USER}@"
fi

# Determine the action
if [ -n "$COMMAND" ]; then
    log_info "Executing command: $COMMAND"
elif [ -n "$SCRIPT_PATH" ]; then
    log_info "Executing script: $SCRIPT_PATH"
fi

for node in "${NODES[@]}"; do
    if [ "$PARALLEL" = true ]; then
        # Run in background
        (
            echo -e "--- [${BOLD}$node${NC}] START ---"
            if [ -n "$COMMAND" ]; then
                ssh ${SSH_OPTIONS} "${SSH_USER_ARG}${node}" "$COMMAND"
            elif [ -n "$SCRIPT_PATH" ]; then
                REMOTE_SCRIPT_PATH="/tmp/$(basename "$SCRIPT_PATH")"
                scp ${SSH_OPTIONS} "$SCRIPT_PATH" "${SSH_USER_ARG}${node}:${REMOTE_SCRIPT_PATH}"
                ssh ${SSH_OPTIONS} "${SSH_USER_ARG}${node}" "chmod +x ${REMOTE_SCRIPT_PATH} && ${REMOTE_SCRIPT_PATH} && rm -f ${REMOTE_SCRIPT_PATH}"
            fi
            rc=$?
            if [ $rc -ne 0 ]; then
                echo -e "--- [${BOLD}$node${NC}] ${RED}FAILED (Exit Code: $rc)${NC} ---"
                # This requires careful handling in parallel, writing to a temp file is safest
                echo "$node" >> "failed_nodes.$$"
            else
                echo -e "--- [${BOLD}$node${NC}] ${GREEN}OK${NC} ---"
            fi
        ) &
        pids+=($!)
    else
        # Run sequentially
        echo -e "\n--- Executing on [${BOLD}$node${NC}] ---"
        if [ -n "$COMMAND" ]; then
            if ! ssh ${SSH_OPTIONS} "${SSH_USER_ARG}${node}" "$COMMAND"; then
                failed_nodes+=("$node")
                log_error "Execution failed on node: $node"
            fi
        elif [ -n "$SCRIPT_PATH" ]; then
            REMOTE_SCRIPT_PATH="/tmp/$(basename "$SCRIPT_PATH")"
            if ! scp ${SSH_OPTIONS} "$SCRIPT_PATH" "${SSH_USER_ARG}${node}:${REMOTE_SCRIPT_PATH}" || \
               ! ssh ${SSH_OPTIONS} "${SSH_USER_ARG}${node}" "chmod +x ${REMOTE_SCRIPT_PATH} && ${REMOTE_SCRIPT_PATH}" || \
               ! ssh ${SSH_OPTIONS} "${SSH_USER_ARG}${node}" "rm -f ${REMOTE_SCRIPT_PATH}"; then
                failed_nodes+=("$node")
                log_error "Script execution failed on node: $node"
                # Best effort cleanup
                ssh ${SSH_OPTIONS} "${SSH_USER_ARG}${node}" "rm -f ${REMOTE_SCRIPT_PATH}" 2>/dev/null || true
            fi
        fi
    fi
done

# Wait for parallel jobs
if [ "$PARALLEL" = true ]; then
    log_info "Waiting for all parallel jobs to complete..."
    for pid in "${pids[@]}"; do
        wait "$pid"
    done

    # Collect results from temp file
    if [ -f "failed_nodes.$$" ]; then
        mapfile -t failed_nodes < "failed_nodes.$$"
        rm "failed_nodes.$$"
    fi
fi

# --- Summary ---
echo
log_info "--- Execution Summary ---"
if [ ${#failed_nodes[@]} -eq 0 ]; then
    log_success "All nodes completed successfully."
    exit 0
else
    log_error "Execution failed on the following nodes:"
    for node in "${failed_nodes[@]}"; do
        echo -e "  - ${RED}$node${NC}"
    done
    exit 1
fi
