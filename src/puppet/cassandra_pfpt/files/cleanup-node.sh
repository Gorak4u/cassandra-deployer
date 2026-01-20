#!/bin/bash
set -euo pipefail

# --- Defaults & Configuration ---
KEYSPACE=""
TABLE_LIST=""
JOBS=0 # 0 means let Cassandra decide
DISK_CHECK_PATH="/var/lib/cassandra/data"
WARNING_THRESHOLD=20
CRITICAL_THRESHOLD=10
LOG_FILE="/var/log/cassandra/cleanup.log"

# --- Logging ---
log_message() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# --- Usage ---
usage() {
    log_message "Usage: $0 [OPTIONS]"
    log_message "Safely runs 'nodetool cleanup' with pre-flight disk space checks."
    log_message "  -k, --keyspace <name>       Specify the keyspace. Required if specifying tables."
    log_message "  -t, --table <name>          Specify a table to clean up. Can be used multiple times."
    log_message "  -j, --jobs <num>            Number of concurrent sstable cleanup jobs. Default: 0 (auto)"
    log_message "  -d, --disk-path <path>      Path to monitor for disk space. Default: $DISK_CHECK_PATH"
    log_message "  -w, --warning <%>           Warning free space threshold (%). Aborts if below. Default: $WARNING_THRESHOLD"
    log_message "  -c, --critical <%>          Critical free space threshold (%). Aborts if below. Default: $CRITICAL_THRESHOLD"
    log_message "  -h, --help                  Show this help message."
    exit 1
}

# --- Argument Parsing ---
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -k|--keyspace) KEYSPACE="$2"; shift ;;
        -t|--table) TABLE_LIST="$TABLE_LIST $2"; shift ;;
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
    log_message "ERROR: A keyspace (-k) must be specified when cleaning up specific tables (-t)."
    exit 1
fi

# --- Main Logic ---
log_message "--- Starting Nodetool Cleanup Manager ---"

# Build the nodetool command
CMD="nodetool cleanup"
TARGET_DESC="full node"

# Add options
if [[ $JOBS -gt 0 ]]; then
    CMD+=" -j $JOBS"
fi

# Add keyspace/table arguments
if [[ -n "$KEYSPACE" ]]; then
    TARGET_DESC="keyspace '$KEYSPACE'"
    CMD+=" -- $KEYSPACE"
    if [[ -n "$TABLE_LIST" ]]; then
        CMD+=$TABLE_LIST
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
    log_message "ERROR: Pre-flight disk space check failed. Aborting cleanup to prevent disk space issues."
    exit 1
fi
log_message "Disk space OK. Proceeding with cleanup."

# Execute the command
if $CMD; then
    log_message "--- Nodetool Cleanup Finished Successfully ---"
    exit 0
else
    CLEANUP_EXIT_CODE=$?
    log_message "ERROR: Nodetool cleanup command failed with exit code $CLEANUP_EXIT_CODE."
    exit $CLEANUP_EXIT_CODE
fi
