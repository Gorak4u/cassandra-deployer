#!/bin/bash
# This file is managed by Puppet.
set -euo pipefail

# --- Defaults & Configuration ---
KEYSPACE=""
TABLE_LIST=()
USER_DEFINED_MODE=false
USER_DEFINED_FILES=()
NODETOOL_OPTIONS=""
DISK_CHECK_PATH="/var/lib/cassandra/data"
CRITICAL_THRESHOLD=85 # Abort if disk usage rises above 85%
CHECK_INTERVAL=30     # Check disk space every 30 seconds
LOG_FILE="/var/log/cassandra/compaction_manager.log"

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
    log_message "${YELLOW}Usage: $0 [OPTIONS] [--user-defined <file1> <file2>...]${NC}"
    log_message "Manages Cassandra compaction with disk space monitoring."
    log_message ""
    log_message "Modes:"
    log_message "  Default:      Compact a keyspace, table, or the entire node."
    log_message "  --user-defined: Compact a specific list of user-defined sstable files."
    log_message ""
    log_message "Options:"
    log_message "  -k, --keyspace <name>         Specify the keyspace to compact. (Not for --user-defined mode)"
    log_message "  -t, --table <name>            Specify a table to compact. Can be used multiple times. (Not for --user-defined mode)"
    log_message "  --nodetool-options <string>   A string of additional options to pass directly to nodetool (e.g., '--split-output -j 2')."
    log_message "  --user-defined                Submit listed files for user-defined compaction. All following args are files."
    log_message "  -d, --disk-path <path>        Path to monitor for disk space. Default: $DISK_CHECK_PATH"
    log_message "  -c, --critical <%>            Critical disk usage threshold (%). Aborts if above. Default: $CRITICAL_THRESHOLD"
    log_message "  -i, --interval <sec>          Interval in seconds to check disk space. Default: $CHECK_INTERVAL"
    log_message "  -h, --help                    Show this help message."
    log_message ""
    log_message "Examples:"
    log_message "  Full node compaction:       $0"
    log_message "  Keyspace compaction:        $0 -k my_keyspace"
    log_message "  Table compaction:           $0 -k my_keyspace -t my_table"
    log_message "  User-defined compaction:    $0 --user-defined /path/to/data.db /path/to/other.db"
    exit 1
}

# --- Argument Parsing ---
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -k|--keyspace) KEYSPACE="$2"; shift 2 ;;
        -t|--table) TABLE_LIST+=("$2"); shift 2 ;;
        --nodetool-options) NODETOOL_OPTIONS="$2"; shift 2 ;;
        -d|--disk-path) DISK_CHECK_PATH="$2"; shift 2 ;;
        -c|--critical) CRITICAL_THRESHOLD="$2"; shift 2 ;;
        -i|--interval) CHECK_INTERVAL="$2"; shift 2 ;;
        --user-defined) USER_DEFINED_MODE=true; shift; USER_DEFINED_FILES=("$@"); break ;; # Capture all remaining args
        -h|--help) usage ;;
        *) log_message "${RED}Unknown parameter passed: $1${NC}"; usage; exit 1 ;;
    esac
done

# --- Main Logic ---
log_message "${BLUE}--- Starting Compaction Manager ---${NC}"

# Build the nodetool command
CMD_BASE="nodetool"
COMPACT_CMD="compact"
CMD=""

if [ "$USER_DEFINED_MODE" = true ]; then
    if [[ -n "$KEYSPACE" || ${#TABLE_LIST[@]} -gt 0 ]]; then
        log_message "${RED}ERROR: Cannot use --keyspace (-k) or --table (-t) with --user-defined.${NC}"
        exit 1
    fi
    if [ ${#USER_DEFINED_FILES[@]} -eq 0 ]; then
        log_message "${RED}ERROR: The --user-defined flag requires at least one sstable file path.${NC}"
        exit 1
    fi
    
    COMPACT_CMD+=" --user-defined"
    # Safely quote file paths
    QUOTED_FILES=()
    for file in "${USER_DEFINED_FILES[@]}"; do
        QUOTED_FILES+=("$(printf '%q' "$file")")
    done

    CMD="$CMD_BASE $COMPACT_CMD ${QUOTED_FILES[*]}"
    TARGET_DESC="user-defined files"
else
    KEYSPACE_ARGS=""
    TARGET_DESC="full node"
    if [[ -n "$KEYSPACE" ]]; then
        TARGET_DESC="keyspace '$KEYSPACE'"
        KEYSPACE_ARGS+=" -- $KEYSPACE"
        if [[ ${#TABLE_LIST[@]} -gt 0 ]]; then
            # Format for nodetool is `... keyspace table1 table2 ...`
            KEYSPACE_ARGS+=" ${TABLE_LIST[*]}"
            CLEAN_TABLE_LIST=$(echo "${TABLE_LIST[*]}")
            TARGET_DESC="table(s) '$CLEAN_TABLE_LIST' in keyspace '$KEYSPACE'"
        fi
    fi
    CMD="$CMD_BASE $COMPACT_CMD $NODETOOL_OPTIONS$KEYSPACE_ARGS"
fi


log_message "${BLUE}Target: $TARGET_DESC${NC}"
log_message "${BLUE}Disk path to monitor: $DISK_CHECK_PATH${NC}"
log_message "${BLUE}Critical disk usage threshold: $CRITICAL_THRESHOLD%${NC}"
log_message "${BLUE}Disk check interval: ${CHECK_INTERVAL}s${NC}"
log_message "Command to be executed: $CMD"

# Pre-flight disk space check
log_message "${BLUE}Performing pre-flight disk usage check...${NC}"
if ! /usr/local/bin/disk-health-check.sh -p "$DISK_CHECK_PATH" -c "$CRITICAL_THRESHOLD"; then
    log_message "${RED}ERROR: Pre-flight disk usage check failed. Aborting compaction to prevent disk space issues.${NC}"
    exit 1
fi
log_message "${GREEN}Disk usage OK.${NC}"

# Pre-flight node state check
log_message "${BLUE}Performing pre-flight node state check...${NC}"
if ! nodetool netstats | grep -q "Mode: NORMAL"; then
    log_message "${YELLOW}ERROR: Node is not in NORMAL mode. It may be streaming, joining, or leaving the cluster.${NC}"
    log_message "Aborting compaction. Please wait for the node to become idle."
    nodetool netstats
    exit 1
fi
log_message "${GREEN}Node state is NORMAL. Proceeding.${NC}"


# Start compaction in the background
log_message "${BLUE}Starting compaction process...${NC}"
eval "$CMD" &
COMPACTION_PID=$!
log_message "${BLUE}Compaction started with PID: $COMPACTION_PID${NC}"

# Monitor the process
while ps -p $COMPACTION_PID > /dev/null; do
    log_message "Compaction running (PID: $COMPACTION_PID). Checking disk usage..."
    
    # Use the existing health check script
    if ! /usr/local/bin/disk-health-check.sh -p "$DISK_CHECK_PATH" -c "$CRITICAL_THRESHOLD"; then
        log_message "${RED}CRITICAL: Disk usage threshold reached. Stopping compaction.${NC}"
        nodetool stop COMPACTION
        # Wait a moment for the stop command to be processed
        sleep 10
        # Check if the process is still running, if so, kill it forcefully
        if ps -p $COMPACTION_PID > /dev/null; then
             log_message "${YELLOW}Nodetool stop did not terminate process. Sending KILL signal to PID $COMPACTION_PID.${NC}"
             kill -9 $COMPACTION_PID
        fi
        log_message "${RED}ERROR: Compaction aborted due to low disk usage.${NC}"
        exit 2
    fi

    log_message "${GREEN}Disk usage OK. Sleeping for $CHECK_INTERVAL seconds.${NC}"
    sleep $CHECK_INTERVAL
done

wait $COMPACTION_PID
COMPACTION_EXIT_CODE=$?

if [[ $COMPACTION_EXIT_CODE -eq 0 ]]; then
    log_message "${GREEN}--- Compaction Manager Finished Successfully ---${NC}"
    exit 0
else
    # This handles cases where compaction fails for reasons other than disk space
    log_message "${RED}ERROR: Compaction process (PID: $COMPACTION_PID) exited with non-zero status: $COMPACTION_EXIT_CODE.${NC}"
    exit $COMPACTION_EXIT_CODE
fi
