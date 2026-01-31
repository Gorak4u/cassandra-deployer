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
INTER_NODE_CHECK_SCRIPT=""
ROLLING_OP=""
INTER_NODE_HEALTH_CHECK=false
CONTINUE_ON_ERROR=false
INTERACTIVE_MODE=false

# --- Color Codes ---
RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
BLUE=$'\033[0;34m'
CYAN=$'\033[0;36m'
BOLD=$'\033[1m'
NC=$'\033[0m' # No Color

# --- Logging (always to stderr) ---
log_info() { echo -e "${BLUE}[INFO]${NC} $1" >&2; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1" >&2; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1" >&2; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }

# --- Wait Function ---
_wait_with_dots() {
    local duration=$1
    local message="${2:-}"

    # Don't show dots if JSON output is enabled
    if [ "$JSON_OUTPUT" = true ]; then
        sleep "$duration"
        return
    fi

    # Using printf for better portability than echo -ne
    printf "%b" "${YELLOW}${message}${NC}"
    for ((i=0; i<duration; i++)); do
        printf "%b" "${YELLOW}.${NC}"
        sleep 1
    done
    printf "\n" # Newline after dots are finished
}


# --- Usage ---
usage() {
    # This function prints to stdout, as is standard for help text.
    echo -e "${BOLD}Cluster Orchestration Tool (cassy.sh)${NC}"
    echo -e "A wrapper to execute commands or scripts on multiple remote nodes via SSH."
    echo -e "Supports static/dynamic node lists, parallel execution, and safe rolling operations."
    echo
    echo -e "${YELLOW}Usage:${NC}"
    echo -e "  $0 [OPTIONS]"
    echo
    echo -e "${YELLOW}OPTIONS${NC}"
    
    # Define two format strings. The padding is calculated to align columns correctly,
    # even with invisible ANSI color codes in the option string.
    local fmt_long="  %-53s %s\n"
    local fmt_short="  %-46s %s\n"
    
    echo -e "${BOLD}Node Selection (choose one method):${NC}"
    printf "$fmt_long" "${BLUE}-n, --nodes ${CYAN}<list>${NC}" "A comma-separated list of target node hostnames or IPs."
    printf "$fmt_long" "${BLUE}-f, --nodes-file ${CYAN}<path>${NC}" "A file containing a list of target nodes, one per line."
    printf "$fmt_long" "${BLUE}--node ${CYAN}<host>${NC}" "Specify a single target node."
    printf "$fmt_long" "${BLUE}--qv-query ${CYAN}\"<query>\"${NC}" "A quoted 'qv' query to dynamically fetch a node list."
    echo

    echo -e "${BOLD}Action (choose one):${NC}"
    printf "$fmt_long" "${BLUE}-c, --command ${CYAN}<command>${NC}" "The shell command to execute on each node."
    printf "$fmt_long" "${BLUE}-s, --script ${CYAN}<path>${NC}" "A local script to copy and execute on each node."
    echo

    echo -e "${BOLD}Execution Control:${NC}"
    printf "$fmt_long" "${BLUE}-l, --user ${CYAN}<user>${NC}" "The SSH user to connect as. Defaults to current user."
    printf "$fmt_long" "${BLUE}-P, --parallel ${CYAN}[N]${NC}" "Execute in parallel. Optional N for batch size."
    printf "$fmt_long" "${BLUE}--ssh-options ${CYAN}<opts>${NC}" "Quoted string of additional SSH options."
    printf "$fmt_long" "${BLUE}--retries ${CYAN}<N>${NC}" "Number of times to retry a failed command. Default: 0."
    printf "$fmt_long" "${BLUE}--timeout ${CYAN}<seconds>${NC}" "Set a timeout for the command on each node. Default: 0 (none)."
    printf "$fmt_short" "${BLUE}--continue-on-error${NC}" "In sequential mode, do not abort if a node fails."
    echo
    
    echo -e "${BOLD}Safety & Rolling Operations:${NC}"
    printf "$fmt_short" "${BLUE}--dry-run${NC}" "Show what would be run, without executing."
    printf "$fmt_short" "${BLUE}-i, --interactive${NC}" "Prompt for confirmation before executing on target nodes."
    printf "$fmt_long" "${BLUE}--rolling-op ${CYAN}<type>${NC}" "Perform a predefined Cassandra rolling operation: 'restart', 'reboot', or 'puppet'."
    printf "$fmt_short" "" "${YELLOW}This enforces sequential execution with a built-in health check.${NC}"
    printf "$fmt_long" "${BLUE}--inter-node-check ${CYAN}<path>${NC}" "For generic rolling ops, run a local check script after each node."
    printf "$fmt_long" "${BLUE}--pre-exec-check ${CYAN}<path>${NC}" "Run a local script before any node is touched."
    printf "$fmt_long" "${BLUE}--post-exec-check ${CYAN}<path>${NC}" "Run a local script after all nodes have been touched."
    echo
    
    echo -e "${BOLD}Output Formatting:${NC}"
    printf "$fmt_short" "${BLUE}--json${NC}" "Output results in machine-readable JSON format."
    printf "$fmt_long" "${BLUE}--output-dir ${CYAN}<path>${NC}" "Save the output from each node to a separate file."
    echo
    
    printf "$fmt_short" "${BLUE}-h, --help${NC}" "Show this help message."
    echo
    
    echo -e "--------------------------------------------------------------------------------"
    echo -e "${YELLOW}ROBUST USAGE EXAMPLES${NC}"
    echo
    echo -e "${BOLD}1. Safe Rolling Restart of a Cassandra Datacenter (Predefined Op)${NC}"
    echo -e "   # Uses the --rolling-op shortcut with a built-in, Cassandra-specific health check."
    echo -e "   $0 --rolling-op restart --qv-query \"-r role_cassandra_pfpt -d AWSLAB\""
    echo
    echo -e "${BOLD}2. Safe Rolling Operation for a Custom Command (Generic)${NC}"
    echo -e "   # First, create your health check script (e.g., my_check.sh):"
    echo -e "   #   #!/bin/bash"
    echo -e "   #   curl --fail http://\${1}:8080/health # \$1 is the node IP from cassy"
    echo -e "   # Make it executable: chmod +x my_check.sh"
    echo -e "   # Then, use it with --inter-node-check:"
    echo -e "   $0 --qv-query \"-r role_webapp\" --inter-node-check ./my_check.sh -c \"sudo systemctl restart my-webapp\""
    echo
    echo -e "${BOLD}3. Parallel Cluster-Wide Repair${NC}"
    echo -e "   # Run repair on all Cassandra nodes in the SC4 datacenter in batches of 5."
    echo -e "   $0 --qv-query \"-r role_cassandra_pfpt -d SC4\" --parallel 5 -c \"sudo cass-ops repair\""
    echo
    echo -e "${BOLD}4. Programmatic Health Auditing${NC}"
    echo -e "   # Get health from all nodes in JSON and use 'jq' to find failures."
    echo -e "   $0 --qv-query \"-r role_cassandra_pfpt\" --json -c \"sudo cass-ops health --json\" | jq '.results[] | select(.status == \"FAILED\")'"
    echo
    echo -e "${BOLD}5. Dry-Run Before a Destructive Operation${NC}"
    echo -e "   # Always check which nodes you are about to decommission before running the command for real."
    echo -e "   $0 --qv-query \"-r role_cassandra_pfpt\" --dry-run -c \"sudo cass-ops decommission\""
    echo
    exit 0
}

# --- Argument Parsing ---
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -n|--nodes) IFS=',' read -r -a NODES <<< "$2"; shift ;;
        -f|--nodes-file)
            if [ ! -f "$2" ]; then log_error "Node file not found: $2"; exit 1; fi
            while IFS= read -r line || [[ -n "$line" ]]; do
                # Ignore empty lines or lines with only whitespace
                if [[ -n "${line// /}" ]]; then
                    NODES+=("$line")
                fi
            done < "$2"
            shift ;;
        --node) NODES=("$2"); shift ;;
        --qv-query) QV_QUERY="$2"; shift ;;
        -c|--command) COMMAND="$2"; shift ;;
        -s|--script) SCRIPT_PATH="$2"; shift ;;
        -l|--user) SSH_USER="$2"; shift ;;
        -P|--parallel)
            PARALLEL=true
            # Check if the next argument is a positive integer for batch size
            if [[ -n "${2:-}" && "$2" =~ ^[1-9][0-9]*$ ]]; then
                PARALLEL_BATCH_SIZE="$2"
                shift # consume the number
            fi
            ;;
        --ssh-options) SSH_OPTIONS="$2"; shift ;;
        --dry-run) DRY_RUN=true ;;
        -i|--interactive) INTERACTIVE_MODE=true ;;
        --json) JSON_OUTPUT=true ;;
        --timeout) TIMEOUT="$2"; shift ;;
        --output-dir) OUTPUT_DIR="$2"; shift ;;
        --retries) RETRIES="$2"; shift ;;
        --rolling-op) ROLLING_OP="$2"; shift ;;
        --pre-exec-check) PRE_EXEC_CHECK="$2"; shift ;;
        --post-exec-check) POST_EXEC_CHECK="$2"; shift ;;
        --inter-node-check) INTER_NODE_CHECK_SCRIPT="$2"; shift ;;
        --continue-on-error) CONTINUE_ON_ERROR=true ;;
        -h|--help) usage ;;
        *) log_error "Unknown parameter passed: $1"; usage; exit 1 ;;
    esac
    shift
done

# --- Validation ---

# Rolling op is a shortcut that sets command and enforces sequential execution
if [ -n "$ROLLING_OP" ]; then
    if [ -n "$COMMAND" ] || [ -n "$SCRIPT_PATH" ]; then
        log_error "Cannot use --command or --script with the --rolling-op shortcut."
        usage; exit 1;
    fi
    if [ "$PARALLEL" = true ]; then
        log_error "--rolling-op can only be used in sequential mode (without --parallel)."
        usage; exit 1;
    fi
    if [ -n "$INTER_NODE_CHECK_SCRIPT" ]; then
        log_error "Cannot use --inter-node-check with --rolling-op. Use one or the other."
        usage; exit 1;
    fi

    # This flag indicates the internal health check should be used
    INTER_NODE_HEALTH_CHECK=true

    # Set command based on operation type
    case "$ROLLING_OP" in
        restart)
            COMMAND="sudo /usr/local/bin/cass-ops restart"
            ;;
        reboot)
            COMMAND="sudo /usr/local/bin/cass-ops reboot"
            ;;
        puppet)
            COMMAND="sudo puppet agent -t"
            ;;
        *)
            log_error "Unknown rolling operation: '$ROLLING_OP'. Use restart, reboot, or puppet."
            usage; exit 1;
            ;;
    esac
fi

if [ ${#NODES[@]} -eq 0 ] && [ -z "$QV_QUERY" ]; then log_error "No target nodes specified. Use --nodes, --nodes-file, --node, or --qv-query."; usage; exit 1; fi
if [ -n "$QV_QUERY" ] && [ ${#NODES[@]} -gt 0 ]; then log_error "Specify either a static node source (--nodes, etc.) or --qv-query, but not both."; usage; exit 1; fi
if [ -z "$COMMAND" ] && [ -z "$SCRIPT_PATH" ]; then log_error "No action specified. Use --command, --script, or --rolling-op."; usage; exit 1; fi
if [ -n "$COMMAND" ] && [ -n "$SCRIPT_PATH" ]; then log_error "Specify either --command or --script, but not both."; usage; exit 1; fi
if [ -n "$SCRIPT_PATH" ] && [ ! -f "$SCRIPT_PATH" ]; then log_error "Script file not found: $SCRIPT_PATH"; exit 1; fi
if { [ -n "$INTER_NODE_CHECK_SCRIPT" ] || [ "$INTER_NODE_HEALTH_CHECK" = true ]; } && [ "$PARALLEL" = true ]; then
    log_error "Inter-node checks can only be used in sequential mode (without --parallel)."
    usage; exit 1;
fi
if [ "$CONTINUE_ON_ERROR" = true ] && [ "$PARALLEL" = true ]; then
    log_error "--continue-on-error can only be used in sequential mode (without --parallel)."
    usage; exit 1;
fi


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
if [ -n "$INTER_NODE_CHECK_SCRIPT" ] && [ ! -x "$INTER_NODE_CHECK_SCRIPT" ]; then log_error "Inter-node check script is not executable: $INTER_NODE_CHECK_SCRIPT"; exit 1; fi

# --- Variable Initialization ---
SSH_USER_ARG=""
if [ -n "$SSH_USER" ]; then
    SSH_USER_ARG="${SSH_USER}@"
fi
failed_nodes=()

# --- Node Discovery ---
if [ -n "$QV_QUERY" ]; then
    log_info "Fetching node list from inventory tool (qv)..."
    if ! command -v qv &> /dev/null; then log_error "'qv' command not found. Cannot fetch inventory."; exit 1; fi
    
    log_info "Running query: qv -t ${QV_QUERY}"
    # Use a while loop for portability, as mapfile is not available in all bash versions.
    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ -n "${line// /}" ]]; then
            NODES+=("$line")
        fi
    done < <(eval "qv -t $QV_QUERY" 2>/dev/null)

    if [ ${#NODES[@]} -eq 0 ]; then log_error "The qv query returned no hosts. Aborting."; exit 1; fi
fi

# --- Interactive Confirmation ---
if [ "$INTERACTIVE_MODE" = true ] && [ "$DRY_RUN" = false ]; then
    log_info "--- INTERACTIVE MODE ---"
    log_info "The following action is about to be executed:"
    log_info "--------------------------------------------------"
    log_info "Target Nodes (${#NODES[@]}): ${CYAN}${NODES[*]}${NC}"
    if [ -n "$COMMAND" ]; then
        log_info "Command:        ${YELLOW}${COMMAND}${NC}"
    elif [ -n "$SCRIPT_PATH" ]; then
        log_info "Script:         ${YELLOW}${SCRIPT_PATH}${NC}"
    fi
    log_info "SSH User:       ${SSH_USER:-$(whoami)}"
    log_info "--------------------------------------------------"
    
    read -p "${BOLD}Proceed with execution? (yes/no): ${NC}" confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        log_warn "Execution aborted by user."
        exit 0
    fi
    log_info "Confirmation received. Proceeding with execution..."
fi

# --- Internal Health Check Function (for rolling ops) ---
_run_health_check() {
    local node_to_check="$1"
    local max_retries=12
    local retry_delay=15

    log_info "--- [Health Check] Verifying stability of ${node_to_check} ---"

    for i in $(seq 1 $max_retries); do
        log_info "  [Health Check] Cycle ${i}/${max_retries} for ${node_to_check}..."

        # Check 1: SSH Connectivity
        if ! ssh ${SSH_OPTIONS} "${SSH_USER_ARG}${node_to_check}" "echo 'SSH OK'" >/dev/null 2>&1; then
            log_warn "    - FAIL: SSH connection failed. Node may not be reachable or SSH service is not ready."
            _wait_with_dots "$retry_delay" "    Retrying in ${retry_delay}s "
            continue
        fi
        log_info "    - OK: SSH is responsive."

        # Check 2: Cluster Health from the node's perspective
        if ssh ${SSH_OPTIONS} "${SSH_USER_ARG}${node_to_check}" "sudo /usr/local/bin/cass-ops cluster-health --silent" >/dev/null 2>&1; then
            log_success "--- [Health Check] SUCCESS: Node ${node_to_check} is healthy and cluster is stable. ---"
            return 0 # Success
        fi

        log_warn "    - FAIL: 'cass-ops cluster-health' failed on the node. Service may not be ready."
        _wait_with_dots "$retry_delay" "    Retrying in ${retry_delay}s "
    done

    log_error "--- [Health Check] CRITICAL: Node ${node_to_check} did not pass health check after ${max_retries} attempts. ---"
    return 1 # Failure
}

# --- Pre-Execution Hooks ---
if [ -n "$PRE_EXEC_CHECK" ]; then
    log_info "--- Running Pre-Execution Check ---"
    if ! "$PRE_EXEC_CHECK"; then
        log_error "Pre-execution check failed. Aborting."
        exit 3
    fi
    log_success "Pre-execution check passed."
fi

# Pre-flight health check for rolling operations
if [ "$INTER_NODE_HEALTH_CHECK" = true ] && [ "$DRY_RUN" = false ]; then
    log_info "--- Running Pre-Rolling Operation Master Health Check ---"
    if ! _run_health_check "${NODES[0]}"; then
        log_error "Initial health check on node ${NODES[0]} failed. Aborting rolling operation before it starts."
        exit 4
    fi
    log_success "Initial health check passed. Starting rolling operation."
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

ACTION_DESC=""
if [ -n "$COMMAND" ]; then ACTION_DESC="command: $COMMAND"; else ACTION_DESC="script: $SCRIPT_PATH"; fi
log_info "Executing $ACTION_DESC"

run_task() {
    local node="$1"
    local output_buffer=""
    local rc=0
    local attempt
    
    for attempt in $(seq 1 $((RETRIES + 1))); do
        # Only log retry attempts, not the first one.
        if [ "$attempt" -gt 1 ]; then
            log_warn "--- [${BOLD}$node${NC}] Retrying... (Attempt $attempt of $((RETRIES + 1))) ---"
            sleep 3 # Brief pause before retry
        fi
        
        local REMOTE_SCRIPT_PATH="/tmp/cassy_remote_script_$$_${attempt}"
        
        local TIMEOUT_CMD=""
        if [ "$TIMEOUT" -gt 0 ]; then TIMEOUT_CMD="timeout $TIMEOUT"; fi

        local SSH_CMD_PREFIX=""
        # Use stdbuf if available for line-buffered output, otherwise proceed without it.
        if command -v stdbuf &> /dev/null; then
            SSH_CMD_PREFIX="stdbuf -oL -eL"
        fi
        
        output_buffer=$({
            if [ -n "$COMMAND" ]; then
                $SSH_CMD_PREFIX $TIMEOUT_CMD ssh ${SSH_OPTIONS} "${SSH_USER_ARG}${node}" "$COMMAND"
            elif [ -n "$SCRIPT_PATH" ]; then
                (
                  scp ${SSH_OPTIONS} "$SCRIPT_PATH" "${SSH_USER_ARG}${node}:${REMOTE_SCRIPT_PATH}" && \
                  $SSH_CMD_PREFIX ssh ${SSH_OPTIONS} "${SSH_USER_ARG}${node}" "chmod +x ${REMOTE_SCRIPT_PATH} && ${REMOTE_SCRIPT_PATH} && rm -f ${REMOTE_SCRIPT_PATH}"
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
    
    # Track failures for the final exit code in parallel mode.
    if [ $rc -ne 0 ] && [ "$PARALLEL" = true ]; then
        # Use flock if available for atomic appends, otherwise just append.
        if command -v flock &> /dev/null; then
            (
                flock 200
                echo "$node" >> "failed_nodes.$$"
            ) 200>failed_nodes.lock
        else
            echo "$node" >> "failed_nodes.$$"
        fi
    fi
    # The return code of this function is the return code of the command
    return $rc
}

if [ "$PARALLEL" = true ]; then
    # Create a temporary file for tracking failed nodes in parallel mode.
    touch "failed_nodes.$$"
    # Create a lock file for safe appends if flock is available
    if command -v flock &> /dev/null; then
        touch "failed_nodes.lock"
        trap 'rm -f "failed_nodes.$$" "failed_nodes.lock"' EXIT
    else
        trap 'rm -f "failed_nodes.$$"' EXIT
    fi


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
            failed_nodes+=("$node")
            if [ "$CONTINUE_ON_ERROR" = true ]; then
                log_warn "Task failed on node ${node}, but --continue-on-error is set. Proceeding to next node."
                # Do not break here, just continue the loop
            else
                log_error "Task failed on node ${node}. Aborting rolling execution."
                break
            fi
        fi

        # If this is a Cassandra rolling operation, run the internal health check.
        if [ "$INTER_NODE_HEALTH_CHECK" = true ] && [ "$DRY_RUN" = false ]; then
            if ! _run_health_check "$node"; then
                log_error "Internal health check failed after operating on node ${node}. Aborting rolling execution."
                failed_nodes+=("$node")
                break
            fi
        fi

        # If the user provided a custom check script, run it.
        if [ -n "$INTER_NODE_CHECK_SCRIPT" ] && [ "$DRY_RUN" = false ]; then
            log_info "--- Running Custom Inter-Node Check from: $INTER_NODE_CHECK_SCRIPT ---"
            if ! "$INTER_NODE_CHECK_SCRIPT" "$node"; then
                log_error "Custom inter-node check failed after operating on node ${node}. Aborting."
                failed_nodes+=("$node")
                break
            fi
            log_success "Custom inter-node check passed."
        fi
    done
fi


# --- Collect Parallel Failures ---
if [ "$PARALLEL" = true ]; then
    if [ -f "failed_nodes.$$" ]; then
        # The temp file might have duplicate entries if flock wasn't available, so sort -u
        # Use a while loop for portability instead of mapfile.
        while IFS= read -r line || [[ -n "$line" ]]; do
             if [[ -n "${line// /}" ]]; then
                failed_nodes+=("$line")
            fi
        done < <(sort -u "failed_nodes.$$")
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
