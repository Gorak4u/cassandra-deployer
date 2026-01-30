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
DRY_RUN=false
JSON_OUTPUT=false
OUTPUT_DIR=""
TIMEOUT=0 # 0 for no timeout

# --- Color Codes ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# --- Logging (always to stderr) ---
log_info() { echo -e "${BLUE}[INFO]${NC} $1" >&2; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1" >&2; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1" >&2; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }

# --- Usage ---
usage() {
    # This function prints to stdout, as is standard for help text.
    echo -e "${BOLD}Cluster Orchestration Tool${NC}"
    echo
    echo -e "A wrapper to execute commands or scripts on multiple remote nodes via SSH."
    echo -e "Supports both static node lists and dynamic inventory fetching via the 'qv' tool."
    echo
    echo -e "${YELLOW}Usage:${NC}"
    echo -e "  $0 [OPTIONS]"
    echo
    echo -e "${YELLOW}Node Selection (choose one method):${NC}"
    echo -e "  -n, --nodes <list>        A comma-separated list of target node hostnames or IPs."
    echo -e "  -f, --nodes-file <path>   A file containing a list of target nodes, one per line."
    echo -e "  --node <host>             Specify a single target node."
    echo -e "  --qv-query \"<query>\"      A quoted string of 'qv' flags to dynamically fetch a node list."
    echo
    echo -e "${YELLOW}Action (choose one):${NC}"
    echo -e "  -c, --command <command>   The shell command to execute on each node."
    echo -e "  -s, --script <path>       The path to a local script to copy and execute on each node."
    echo
    echo -e "${YELLOW}Execution Options:${NC}"
    echo -e "  -l, --user <user>         The SSH user to connect as. Defaults to the current user."
    echo -e "  -P, --parallel            Execute on all nodes in parallel instead of sequentially."
    echo -e "  --ssh-options <opts>      Quoted string of additional options for the SSH command (e.g., \"-i /path/key.pem\")."
    echo
    echo -e "${YELLOW}Output & Safety:${NC}"
    echo -e "  --dry-run                 Show which nodes would be targeted and what command would run, without executing."
    echo -e "  --json                    Output results in a machine-readable JSON format. Suppresses normal logging on stdout."
    echo -e "  --timeout <seconds>       Set a timeout in seconds for the command on each node. `0` means no timeout. (Requires 'timeout' command)."
    echo -e "  --output-dir <path>       Save the output from each node to a separate file in the specified directory."
    echo
    echo -e "  -h, --help                Show this help message."
    exit 1
}

# --- Argument Parsing ---
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -n|--nodes) IFS=',' read -r -a NODES <<< "$2"; shift ;;
        -f|--nodes-file)
            if [ ! -f "$2" ]; then log_error "Node file not found: $2"; exit 1; fi
            NODES=()
            while IFS= read -r line; do
                if [ -n "$line" ]; then NODES+=("$line"); fi
            done < "$2"
            shift ;;
        --node) NODES=("$2"); shift ;;
        --qv-query) QV_QUERY="$2"; shift ;;
        -c|--command) COMMAND="$2"; shift ;;
        -s|--script) SCRIPT_PATH="$2"; shift ;;
        -l|--user) SSH_USER="$2"; shift ;;
        -P|--parallel) PARALLEL=true ;;
        --ssh-options) SSH_OPTIONS="$2"; shift ;;
        --dry-run) DRY_RUN=true ;;
        --json) JSON_OUTPUT=true ;;
        --timeout) TIMEOUT="$2"; shift ;;
        --output-dir) OUTPUT_DIR="$2"; shift ;;
        -h|--help) usage ;;
        *) log_error "Unknown parameter passed: $1"; usage ;;
    esac
    shift
done

# --- Validation ---
if [ ${#NODES[@]} -eq 0 ] && [ -z "$QV_QUERY" ]; then log_error "No target nodes specified. Use --nodes, --nodes-file, --node, or --qv-query."; usage; fi
if [ -n "$QV_QUERY" ] && [ ${#NODES[@]} -gt 0 ]; then log_error "Specify either a static node source (--nodes, etc.) or --qv-query, but not both."; usage; fi
if [ -z "$COMMAND" ] && [ -z "$SCRIPT_PATH" ]; then log_error "No action specified. Use --command or --script."; usage; fi
if [ -n "$COMMAND" ] && [ -n "$SCRIPT_PATH" ]; then log_error "Specify either --command or --script, but not both."; usage; fi
if [ -n "$SCRIPT_PATH" ] && [ ! -f "$SCRIPT_PATH" ]; then log_error "Script file not found: $SCRIPT_PATH"; exit 1; fi

if [ -n "$OUTPUT_DIR" ]; then
    if ! mkdir -p "$OUTPUT_DIR"; then log_error "Cannot create or write to output directory: $OUTPUT_DIR"; exit 1; fi
    OUTPUT_DIR=$(cd "$OUTPUT_DIR" && pwd) # Get absolute path
fi
if [[ ! "$TIMEOUT" =~ ^[0-9]+$ ]]; then log_error "Timeout must be a non-negative integer."; exit 1; fi
if [ "$TIMEOUT" -gt 0 ] && ! command -v timeout &> /dev/null; then
    log_warn "'timeout' command not found, the --timeout flag will be ignored."
    TIMEOUT=0
fi

# --- Node Discovery ---
if [ -n "$QV_QUERY" ]; then
    log_info "Fetching node list from inventory tool (qv)..."
    if ! command -v qv &> /dev/null; then log_error "'qv' command not found. Cannot fetch inventory."; exit 1; fi
    
    log_info "Running query: qv -t ${QV_QUERY}"
    NODES=()
    while IFS= read -r line; do
        if [ -n "$line" ]; then NODES+=("$line"); fi
    done < <(eval "qv -t $QV_QUERY" 2>/dev/null)

    if [ ${#NODES[@]} -eq 0 ]; then log_error "The qv query returned no hosts. Aborting."; exit 1; fi
fi

# --- Dry-Run ---
if [ "$DRY_RUN" = true ]; then
    log_info "--- DRY RUN MODE ---"
    log_info "Action will NOT be executed."
    log_info "Target nodes (${#NODES[@]}): ${NODES[*]}"
    if [ -n "$COMMAND" ]; then
        log_info "Command: $COMMAND"
    elif [ -n "$SCRIPT_PATH" ]; then
        log_info "Script: $SCRIPT_PATH"
    fi
    exit 0
fi

# --- JSON/Output Setup ---
JSON_TEMP_DIR=""
if [ "$JSON_OUTPUT" = true ]; then
    if ! command -v jq &> /dev/null; then log_error "'jq' command not found, but is required for --json output."; exit 1; fi
    JSON_TEMP_DIR=$(mktemp -d cassy.results.XXXXXX)
    # Cleanup temp dir on exit
    trap 'rm -rf "$JSON_TEMP_DIR"' EXIT
fi

# --- Execution ---
log_info "Target nodes: ${NODES[*]}"
PARALLEL_MODE=$(if [ "$PARALLEL" = true ]; then echo "Parallel"; else echo "Sequential"; fi)
log_info "Execution mode: ${PARALLEL_MODE}"
log_info "SSH user: ${SSH_USER:-$(whoami)}"

pids=()
failed_nodes=()
SSH_USER_ARG=""
if [ -n "$SSH_USER" ]; then SSH_USER_ARG="${SSH_USER}@"; fi
ACTION_DESC=""
if [ -n "$COMMAND" ]; then ACTION_DESC="command: $COMMAND"; else ACTION_DESC="script: $SCRIPT_PATH"; fi
log_info "Executing $ACTION_DESC"

for node in "${NODES[@]}"; do
    TIMEOUT_CMD=""
    if [ "$TIMEOUT" -gt 0 ]; then TIMEOUT_CMD="timeout $TIMEOUT"; fi
    
    NODE_LOG_FILE=""
    if [ -n "$OUTPUT_DIR" ]; then NODE_LOG_FILE="${OUTPUT_DIR}/${node}.log"; fi

    run_task() {
        local output
        local rc=0
        
        output=$({
            if [ -n "$COMMAND" ]; then
                $TIMEOUT_CMD ssh ${SSH_OPTIONS} "${SSH_USER_ARG}${node}" "$COMMAND"
            elif [ -n "$SCRIPT_PATH" ]; then
                REMOTE_SCRIPT_PATH="/tmp/$(basename "$SCRIPT_PATH")"
                $TIMEOUT_CMD scp ${SSH_OPTIONS} "$SCRIPT_PATH" "${SSH_USER_ARG}${node}:${REMOTE_SCRIPT_PATH}" && \
                $TIMEOUT_CMD ssh ${SSH_OPTIONS} "${SSH_USER_ARG}${node}" "chmod +x ${REMOTE_SCRIPT_PATH} && ${REMOTE_SCRIPT_PATH} && rm -f ${REMOTE_SCRIPT_PATH}"
            fi
        } 2>&1)
        rc=$?

        if [ -n "$NODE_LOG_FILE" ]; then echo "$output" > "$NODE_LOG_FILE"; fi

        if [ "$JSON_OUTPUT" = true ]; then
            local status_text="SUCCESS"; if [ $rc -ne 0 ]; then status_text="FAILED"; fi
            # Use jq to safely create a JSON object for this node's result
            jq -n --arg node "$node" \
                  --arg status "$status_text" \
                  --argjson rc "$rc" \
                  --arg output "$output" \
                  '{node: $node, status: $status, exit_code: $rc, output: $output}' > "${JSON_TEMP_DIR}/${node}.json"
        else
            echo -e "--- [${BOLD}$node${NC}] START ---"
            echo "$output"
            if [ $rc -ne 0 ]; then
                echo -e "--- [${BOLD}$node${NC}] ${RED}FAILED (Exit Code: $rc)${NC} ---"
            else
                echo -e "--- [${BOLD}$node${NC}] ${GREEN}OK${NC} ---"
            fi
        fi

        # Track failures for the final exit code
        if [ $rc -ne 0 ]; then
            # In parallel, this write must be atomic. Appending to a file is safe.
            if [ "$PARALLEL" = true ]; then
                echo "$node" >> "failed_nodes.$$"
            else
                failed_nodes+=("$node")
            fi
        fi
    }

    if [ "$PARALLEL" = true ]; then
        run_task &
        pids+=($!)
    else
        log_info "\n--- Executing on [${BOLD}$node${NC}] ---"
        run_task
    fi
done

# --- Wait & Collect ---
if [ "$PARALLEL" = true ]; then
    log_info "Waiting for all parallel jobs to complete..."
    for pid in "${pids[@]}"; do
        wait "$pid"
    done
    # Collect results from temp file
    if [ -f "failed_nodes.$$" ]; then
        while IFS= read -r line; do
            if [ -n "$line" ]; then failed_nodes+=("$line"); fi
        done < "failed_nodes.$$"
        rm "failed_nodes.$$"
    fi
fi

# --- Final Output ---
if [ "$JSON_OUTPUT" = true ]; then
    # Combine all the individual JSON result files into a single JSON array
    jq -s . "${JSON_TEMP_DIR}"/*.json
    # Exit code is determined by whether any nodes failed, consistent with non-JSON mode
    if [ ${#failed_nodes[@]} -eq 0 ]; then exit 0; else exit 1; fi
fi

log_info "--- Execution Summary ---"
if [ ${#failed_nodes[@]} -eq 0 ]; then
    log_success "All nodes completed successfully."
    exit 0
else
    log_error "Execution failed on the following nodes:"
    for node in "${failed_nodes[@]}"; do
        echo -e "  - ${RED}$node${NC}" >&2
    done
    exit 1
fi
