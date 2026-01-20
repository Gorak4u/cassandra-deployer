#!/bin/bash
set -euo pipefail

# --- Defaults & Configuration ---
KEYSPACE=""
TABLE=""
DISK_CHECK_PATH="/var/lib/cassandra/data"
CRITICAL_THRESHOLD=15 # Abort if free space drops below 15%
CHECK_INTERVAL=30     # Check disk space every 30 seconds
LOG_FILE="/var/log/cassandra/compaction_manager.log"

# --- Logging ---
log_message() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# --- Usage ---
usage() {
    log_message "Usage: $0 [OPTIONS]"
    log_message "Manages Cassandra compaction with disk space monitoring."
    log_message "  -k, --keyspace <name>    Specify the keyspace to compact. (Required for -t)"
    log_message "  -t, --table <name>       Specify the table to compact."
    log_message "  -d, --disk-path <path>   Path to monitor for disk space. Default: $DISK_CHECK_PATH"
    log_message "  -c, --critical <%>       Critical free space threshold (%). Aborts if below. Default: $CRITICAL_THRESHOLD"
    log_message "  -i, --interval <sec>     Interval in seconds to check disk space. Default: $CHECK_INTERVAL"
    log_message "  -h, --help               Show this help message."
    log_message ""
    log_message "Examples:"
    log_message "  Full node compaction:       $0"
    log_message "  Keyspace compaction:        $0 -k my_keyspace"
    log_message "  Table compaction:           $0 -k my_keyspace -t my_table"
    exit 1
}

# --- Argument Parsing ---
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -k|--keyspace) KEYSPACE="$2"; shift ;;
        -t|--table) TABLE="$2"; shift ;;
        -d|--disk-path) DISK_CHECK_PATH="$2"; shift ;;
        -c|--critical) CRITICAL_THRESHOLD="$2"; shift ;;
        -i|--interval) CHECK_INTERVAL="$2"; shift ;;
        -h|--help) usage ;;
        *) log_message "Unknown parameter passed: $1"; usage ;;
    esac
    shift
done

if [[ -n "$TABLE" && -z "$KEYSPACE" ]]; then
    log_message "ERROR: A keyspace (-k) must be specified when compacting a table (-t)."
    exit 1
fi

# --- Main Logic ---
log_message "--- Starting Compaction Manager ---"

# Build the nodetool command
CMD="nodetool compact"
TARGET_DESC="full node"
if [[ -n "$KEYSPACE" ]]; then
    CMD+=" $KEYSPACE"
    TARGET_DESC="keyspace '$KEYSPACE'"
    if [[ -n "$TABLE" ]]; then
        CMD+=" $TABLE"
        TARGET_DESC="table '$TABLE'"
    fi
fi

log_message "Target: $TARGET_DESC"
log_message "Disk path to monitor: $DISK_CHECK_PATH"
log_message "Critical free space threshold: $CRITICAL_THRESHOLD%"
log_message "Disk check interval: $CHECK_INTERVALs"

# Start compaction in the background
log_message "Starting compaction process..."
$CMD &
COMPACTION_PID=$!
log_message "Compaction started with PID: $COMPACTION_PID"

# Monitor the process
while ps -p $COMPACTION_PID > /dev/null; do
    log_message "Compaction running (PID: $COMPACTION_PID). Checking disk space..."
    
    # Use the existing health check script
    if ! /usr/local/bin/disk-health-check.sh -p "$DISK_CHECK_PATH" -c "$CRITICAL_THRESHOLD"; then
        log_message "CRITICAL: Disk space threshold reached. Stopping compaction."
        nodetool stop COMPACTION
        # Wait a moment for the stop command to be processed
        sleep 10
        # Check if the process is still running, if so, kill it forcefully
        if ps -p $COMPACTION_PID > /dev/null; then
             log_message "Nodetool stop did not terminate process. Sending KILL signal to PID $COMPACTION_PID."
             kill -9 $COMPACTION_PID
        fi
        log_message "ERROR: Compaction aborted due to low disk space."
        exit 2
    fi

    log_message "Disk space OK. Sleeping for $CHECK_INTERVAL seconds."
    sleep $CHECK_INTERVAL
done

wait $COMPACTION_PID
COMPACTION_EXIT_CODE=$?

if [[ $COMPACTION_EXIT_CODE -eq 0 ]]; then
    log_message "--- Compaction Manager Finished Successfully ---"
    exit 0
else
    # This handles cases where compaction fails for reasons other than disk space
    log_message "ERROR: Compaction process (PID: $COMPACTION_PID) exited with non-zero status: $COMPACTION_EXIT_CODE."
    exit $COMPACTION_EXIT_CODE
fi
