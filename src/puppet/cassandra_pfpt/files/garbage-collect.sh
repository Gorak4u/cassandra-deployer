#!/bin/bash
set -euo pipefail

# --- Defaults & Configuration ---
KEYSPACE=""
TABLE_LIST=""
GRANULARITY="ROW"
JOBS=0 # 0 means let Cassandra decide
DISK_CHECK_PATH="/var/lib/cassandra/data"
WARNING_THRESHOLD=30
CRITICAL_THRESHOLD=20
LOG_FILE="/var/log/cassandra/garbagecollect.log"

# --- Logging ---
log_message() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# --- Usage ---
usage() {
    log_message "Usage: $0 [OPTIONS]"
    log_message "Safely runs 'nodetool garbagecollect' with pre-flight disk space checks."
    log_message "  -k, --keyspace <name>       Specify the keyspace. Required if specifying tables."
    log_message "  -t, --table <name>          Specify a table to collect. Can be used multiple times."
    log_message "  -g, --granularity <CELL|ROW> Granularity of tombstones to remove. Default: ROW"
    log_message "  -j, --jobs <num>            Number of concurrent sstable garbage collection jobs. Default: 0 (auto)"
    log_message "  -d, --disk-path <path>      Path to monitor for disk space. Default: $DISK_CHECK_PATH"
    log_message "  -w, --warning <%>           Warning free space threshold (%). Aborts if below. Default: $WARNING_THRESHOLD"
    log_message "  -c, --critical <%>          Critical free space threshold (%). Aborts if below. Default: $CRITICAL_THRESHOLD"
    log_message "  -h, --help                  Show this help message."
    log_message ""
    log_message "Examples:"
    log_message "  Collect on entire node:       $0"
    log_message "  Collect on a keyspace:        $0 -k my_keyspace"
    log_message "  Collect on specific tables:   $0 -k my_keyspace -t users -t audit_log"
    log_message "  Collect with cell granularity: $0 -k my_keyspace -t users -g CELL"
    exit 1
}

# --- Argument Parsing ---
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -k|--keyspace) KEYSPACE="$2"; shift ;;
        -t|--table) TABLE_LIST="$TABLE_LIST $2"; shift ;;
        -g|--granularity) GRANULARITY="$2"; shift ;;
        -j|--jobs) JOBS="$2"; shift ;;
        -d|--disk-path) DISK_CHECK_PATH="$2"; shift ;;
        -w|--warning) WARNING_THRESHOLD="$2"; shift ;;
        -c|--critical) CRITICAL_THRESHOLD="$2"; shift ;;
        -h|--help) usage ;;
        *) log_message "Unknown parameter passed: $1"; usage ;;
    esac
    shift
done

if [[ -n "$TABLE_LIST" && -z "$KEYSPACE" ]]; then
    log_message "ERROR: A keyspace (-k) must be specified when collecting on specific tables (-t)."
    exit 1
fi

# --- Main Logic ---
log_message "--- Starting Garbage Collect Manager ---"

# Build the nodetool command
CMD="nodetool garbagecollect"
TARGET_DESC="full node"

# Add options
CMD+=" -g $GRANULARITY"
if [[ $JOBS -gt 0 ]]; then
    CMD+=" -j $JOBS"
fi

# Add keyspace/table arguments
if [[ -n "$KEYSPACE" ]]; then
    TARGET_DESC="keyspace '$KEYSPACE'"
    CMD+=" -- $KEYSPACE"
    if [[ -n "$TABLE_LIST" ]]; then
        CMD+=$TABLE_LIST
        # Remove leading space for description
        CLEAN_TABLE_LIST=$(echo "$TABLE_LIST" | sed 's/^ *//g')
        TARGET_DESC="table(s) '$CLEAN_TABLE_LIST' in keyspace '$KEYSPACE'"
    fi
fi

log_message "Target: $TARGET_DESC"
log_message "Disk path to check: $DISK_CHECK_PATH"
log_message "Warning free space threshold: $WARNING_THRESHOLD%"
log_message "Critical free space threshold: $CRITICAL_THRESHOLD%"
log_message "Command to be executed: $CMD"

# Pre-flight disk space check
log_message "Performing pre-flight disk space check..."
if ! /usr/local/bin/disk-health-check.sh -p "$DISK_CHECK_PATH" -w "$WARNING_THRESHOLD" -c "$CRITICAL_THRESHOLD"; then
    log_message "ERROR: Pre-flight disk space check failed. Aborting garbage collection to prevent disk space issues."
    exit 1
fi
log_message "Disk space OK. Proceeding with garbage collection."

# Execute the command
if $CMD; then
    log_message "--- Garbage Collect Finished Successfully ---"
    exit 0
else
    GC_EXIT_CODE=$?
    log_message "ERROR: Garbage collection command failed with exit code $GC_EXIT_CODE."
    exit $GC_EXIT_CODE
fi
