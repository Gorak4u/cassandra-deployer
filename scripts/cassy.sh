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
PARALLEL_BATCH_SIZE=0
QV_QUERY=""
DRY_RUN=false
JSON_OUTPUT=false
OUTPUT_DIR=""
TIMEOUT=0 # 0 for no timeout
RETRIES=0
PRE_EXEC_CHECK=""
POST_EXEC_CHECK=""
INTER_NODE_CHECK=""

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
    echo -e "  -P, --parallel [N]        Execute in parallel. By default on all nodes, or with a concurrency of N if provided."
    echo -e "  --ssh-options <opts>      Quoted string of additional options for the SSH command (e.g., \"-i /path/key.pem\")."
    echo
    echo -e "${YELLOW}Output & Safety:${NC}"
    echo -e "  --dry-run                 Show which nodes would be targeted and what command would run, without executing."
    echo -e "  --json                    Output results in a machine-readable JSON format. Suppresses normal logging on stdout."
    echo -e "  --timeout <seconds>       Set a timeout in seconds for the command on each node. \`0\` means no timeout. (Requires 'timeout' command)."
    echo -e "  --output-dir <path>       Save the output from each node to a separate file in the specified directory."
    echo
    echo -e "${YELLOW}Automation & Safety:${NC}"
    echo -e "  --retries <N>             Number of times to retry a failed command on a node. Default: 0."
    echo -e "  --pre-exec-check <path>   A local script to run before executing on any nodes. If it fails, cassy.sh aborts."
    echo -e "  --post-exec-check <path>  A local script to run after executing on all nodes."
    echo -e "  --inter-node-check <path> A local script to run after each node in sequential mode. If it fails, the rolling execution stops."
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
            mapfile -t NODES < "$2"
            shift ;;
        --node) NODES=("$2"); shift ;;
        --qv-query) QV_QUERY="$2"; shift ;;
        -c|--command) COMMAND="$2"; shift ;;
        -s|--script) SCRIPT_PATH="$2"; shift ;;
        -l|--user) SSH_USER="$2"; shift ;;
        -P|--parallel)
            PARALLEL=true
            # Check if the next argument is a positive integer for batch size
            if [[ -n "$2" && "$2" =~ ^[1-9][0-9]*$ ]]; then
                PARALLEL_BATCH_SIZE="$2"
                shift # consume the number
            fi
            ;;
        --ssh-options) SSH_OPTIONS="$2"; shift ;;
        --dry-run) DRY_RUN=true ;;
        --json) JSON_OUTPUT=true ;;
        --timeout) TIMEOUT="$2"; shift ;;
        --output-dir) OUTPUT_DIR="$2"; shift ;;
        --retries) RETRIES="$2"; shift ;;
        --pre-exec-check) PRE_EXEC_CHECK="$2"; shift ;;
        --post-exec-check) POST_EXEC_CHECK="$2"; shift ;;
        --inter-node-check) INTER_NODE_CHECK="$2"; shift ;;
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
if [ "$PARALLEL" = true ] && [ -n "$INTER_NODE_CHECK" ]; then log_error "--inter-node-check can only be used in sequential mode (without --parallel)."; exit 1; fi


if [ -n "$OUTPUT_DIR" ]; then
    if ! mkdir -p "$OUTPUT_DIR"; then log_error "Cannot create or write to output directory: $OUTPUT_DIR"; exit 1; fi
    OUTPUT_DIR=$(cd "$OUTPUT_DIR" && pwd) # Get absolute path
fi
if [[ ! "$TIMEOUT" =~ ^[0-9]+$ ]]; then log_error "Timeout must be a non-negative integer."; exit 1; fi
if [ "$TIMEOUT" -gt 0 ] && ! command -v timeout &> /dev/null; then
    log_warn "'timeout' command not found, the --timeout flag will be ignored."
    TIMEOUT=0
fi
if [[ ! "$RETRIES" =~ ^[0-9]+$ ]]; then log_error "Retries must be a non-negative integer."; exit 1; fi
if [ -n "$PRE_EXEC_CHECK" ] && [ ! -x "$PRE_EXEC_CHECK" ]; then log_error "Pre-execution check script is not executable: $PRE_EXEC_CHECK"; exit 1; fi
if [ -n "$POST_EXEC_CHECK" ] && [ ! -x "$POST_EXEC_CHECK" ]; then log_error "Post-execution check script is not executable: $POST_EXEC_CHECK"; exit 1; fi
if [ -n "$INTER_NODE_CHECK" ] && [ ! -x "$INTER_NODE_CHECK" ]; then log_error "Inter-node check script is not executable: $INTER_NODE_CHECK"; exit 1; fi

# --- Node Discovery ---
if [ -n "$QV_QUERY" ]; then
    log_info "Fetching node list from inventory tool (qv)..."
    if ! command -v qv &> /dev/null; then log_error "'qv' command not found. Cannot fetch inventory."; exit 1; fi
    
    log_info "Running query: qv -t ${QV_QUERY}"
    mapfile -t NODES < <(eval "qv -t $QV_QUERY" 2>/dev/null)

    if [ ${#NODES[@]} -eq 0 ]; then log_error "The qv query returned no hosts. Aborting."; exit 1; fi
fi

# --- Pre-Execution Hook ---
if [ -n "$PRE_EXEC_CHECK" ]; then
    log_info "--- Running Pre-Execution Check ---"
    if ! "$PRE_EXEC_CHECK"; then
        log_error "Pre-execution check failed. Aborting."
        exit 3
    fi
    log_success "Pre-execution check passed."
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

PARALLEL_MODE="Sequential"
if [ "$PARALLEL" = true ]; then
    if [ "$PARALLEL_BATCH_SIZE" -gt 0 ]; then
        PARALLEL_MODE="Parallel (Concurrency: $PARALLEL_BATCH_SIZE)"
    else
        PARALLEL_MODE="Parallel (All Nodes)"
    fi
fi
log_info "Execution mode: ${PARALLEL_MODE}"
log_info "SSH user: ${SSH_USER:-$(whoami)}"

failed_nodes=()
SSH_USER_ARG=""
if [ -n "$SSH_USER" ]; then SSH_USER_ARG="${SSH_USER}@"; fi
ACTION_DESC=""
if [ -n "$COMMAND" ]; then ACTION_DESC="command: $COMMAND"; else ACTION_DESC="script: $SCRIPT_PATH"; fi
log_info "Executing $ACTION_DESC"

run_task() {
    local node="$1"
    local output_buffer=""
    local rc=0
    local attempt
    local REMOTE_SCRIPT_PATH
    
    for attempt in $(seq 1 $((RETRIES + 1))); do
        # Only log retry attempts, not the first one.
        if [ "$attempt" -gt 1 ]; then
            log_warn "--- [${BOLD}$node${NC}] Retrying... (Attempt $attempt of $((RETRIES + 1))) ---"
            sleep 3 # Brief pause before retry
        fi
        
        REMOTE_SCRIPT_PATH="/tmp/cassy_remote_script_$$_${attempt}"
        
        local TIMEOUT_CMD=""
        if [ "$TIMEOUT" -gt 0 ]; then TIMEOUT_CMD="timeout $TIMEOUT"; fi
        
        output_buffer=$({
            if [ -n "$COMMAND" ]; then
                # Use stdbuf to make output line-buffered
                stdbuf -oL -eL $TIMEOUT_CMD ssh ${SSH_OPTIONS} "${SSH_USER_ARG}${node}" "$COMMAND"
            elif [ -n "$SCRIPT_PATH" ]; then
                # The script execution part is more complex to buffer line by line.
                # It's better to capture its full output at once.
                (
                  scp ${SSH_OPTIONS} "$SCRIPT_PATH" "${SSH_USER_ARG}${node}:${REMOTE_SCRIPT_PATH}" && \
                  ssh ${SSH_OPTIONS} "${SSH_USER_ARG}${node}" "chmod +x ${REMOTE_SCRIPT_PATH} && ${REMOTE_SCRIPT_PATH} && rm -f ${REMOTE_SCRIPT_PATH}"
                )
            fi
        } 2>&1)
        rc=$?

        # If the command was successful, break out of the retry loop.
        if [ "$rc" -eq 0 ]; then
            break
        fi
    done

    # The final status is based on the last attempt.
    if [ -n "$OUTPUT_DIR" ]; then echo "$output_buffer" > "${OUTPUT_DIR}/${node}.log"; fi

    if [ "$JSON_OUTPUT" = true ]; then
        local status_text="SUCCESS"; if [ $rc -ne 0 ]; then status_text="FAILED"; fi
        jq -n --arg node "$node" \
              --arg status "$status_text" \
              --argjson rc "$rc" \
              --arg output "$output_buffer" \
              '{node: $node, status: $status, exit_code: $rc, output: $output}' > "${JSON_TEMP_DIR}/${node}.json"
    else
        # Print the buffered output all at once
        echo -e "--- [${BOLD}$node${NC}] START ---"
        echo "$output_buffer"
        if [ $rc -ne 0 ]; then
            echo -e "--- [${BOLD}$node${NC}] ${RED}FAILED (Exit Code: $rc)${NC} ---"
        else
            echo -e "--- [${BOLD}$node${NC}] ${GREEN}OK${NC} ---"
        fi
    fi
    
    # Track failures for the final exit code
    if [ $rc -ne 0 ]; then
        # This is safe for both parallel and sequential mode.
        # In parallel mode, it's a file. In sequential, it's an array.
        # The lock makes appending to the file safe.
        (
            flock 200
            echo "$node" >> "failed_nodes.$$"
        ) 200>failed_nodes.lock
    fi
    # The return code of this function is the return code of the command
    return $rc
}

if [ "$PARALLEL" = true ]; then
    # Create a temporary file for tracking failed nodes in parallel mode.
    touch "failed_nodes.$$"
    # Create a lock file for safe appends
    touch "failed_nodes.lock"
    trap 'rm -f "failed_nodes.$$" "failed_nodes.lock"' EXIT

    if [ "$PARALLEL_BATCH_SIZE" -gt 0 ]; then
        # --- Worker Pool Parallel Execution ---
        log_info "--- Executing with a maximum of ${PARALLEL_BATCH_SIZE} concurrent jobs ---"

        fifo=$(mktemp -u)
        mkfifo "$fifo"
        exec 3<>"$fifo"
        rm "$fifo"

        for (( i=0; i<PARALLEL_BATCH_SIZE; i++ )); do
            printf '\n' >&3
        done

        all_pids=()
        for node in "${NODES[@]}"; do
            read -r -u 3
            (
                run_task "$node"
                printf '\n' >&3
            ) &
            all_pids+=($!)
        done

        log_info "All jobs started. Waiting for the last running jobs to finish..."
        wait "${all_pids[@]}"
        exec 3>&-
    else
        # --- Full Parallel Execution (All nodes at once) ---
        pids=()
        for node in "${NODES[@]}"; do
            run_task "$node" &
            pids+=($!)
        done
        log_info "Waiting for all parallel jobs to complete..."
        for pid in "${pids[@]}"; do
            wait "$pid" || true # a failed command should not stop the wait
        done
    fi
else
    # --- Sequential Execution Logic ---
    for node in "${NODES[@]}"; do
        log_info "\n--- Executing on [${BOLD}$node${NC}] ---"
        if ! run_task "$node"; then
            log_error "Task failed on node ${node}. Aborting rolling execution."
            # The failed node is already added to the list by run_task
            break
        fi

        # If an inter-node check is specified, run it.
        if [ -n "$INTER_NODE_CHECK" ]; then
            log_info "--- Running Inter-Node Check after operating on ${node} ---"
            # Pass the hostname of the node that was just operated on to the check script
            if ! "$INTER_NODE_CHECK" "$node"; then
                log_error "Inter-node check failed after node ${node}. Aborting rolling execution."
                # Manually add the node that caused the failure, as the task itself succeeded.
                failed_nodes+=("$node")
                break
            fi
            log_success "Inter-node check passed."
        fi
    fi
fi


# --- Collect Parallel Failures ---
if [ "$PARALLEL" = true ]; then
    if [ -f "failed_nodes.$$" ]; then
        mapfile -t failed_nodes < "failed_nodes.$$"
    fi
fi

# --- Post-Execution Hook ---
if [ -n "$POST_EXEC_CHECK" ]; then
    log_info "--- Running Post-Execution Check ---"
    if ! "$POST_EXEC_CHECK"; then
        # This is a warning, not a fatal error for the whole script run.
        log_warn "Post-execution check failed."
    else
        log_success "Post-execution check passed."
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
