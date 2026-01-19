
export const maintenanceScripts = {
      'cassandra-upgrade-precheck.sh': '#!/bin/bash\\n# Placeholder for cassandra-upgrade-precheck.sh\\necho "Cassandra Upgrade Pre-check Script"',
      'repair-node.sh': '#!/bin/bash\\nnodetool repair -pr',
      'cleanup-node.sh': `#!/bin/bash
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
`,
      'garbage-collect.sh': `#!/bin/bash
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
`,
      'upgrade-sstables.sh': `#!/bin/bash
set -euo pipefail

# --- Defaults & Configuration ---
KEYSPACE=""
TABLE_LIST=""
JOBS=0 # 0 means let Cassandra decide
DISK_CHECK_PATH="/var/lib/cassandra/data"
WARNING_THRESHOLD=30 # Upgrade can be disk intensive
CRITICAL_THRESHOLD=20
LOG_FILE="/var/log/cassandra/upgradesstables.log"

# --- Logging ---
log_message() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# --- Usage ---
usage() {
    log_message "Usage: $0 [OPTIONS]"
    log_message "Safely runs 'nodetool upgradesstables' with pre-flight disk space checks."
    log_message "This is typically run after a major version upgrade of Cassandra."
    log_message "  -k, --keyspace <name>       Specify the keyspace. Required if specifying tables."
    log_message "  -t, --table <name>          Specify a table to upgrade. Can be used multiple times."
    log_message "  -j, --jobs <num>            Number of concurrent sstable upgrade jobs. Default: 0 (auto)"
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
    log_message "ERROR: A keyspace (-k) must be specified when upgrading specific tables (-t)."
    exit 1
fi

# --- Main Logic ---
log_message "--- Starting SSTable Upgrade Manager ---"

# Build the nodetool command
CMD="nodetool upgradesstables"
TARGET_DESC="all keyspaces and tables"

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
else
    # If no keyspace is provided, nodetool upgrades all sstables. The -a flag is implied.
    CMD+=" -a"
fi

log_message "Target: $TARGET_DESC"
log_message "Disk path to check: $DISK_CHECK_PATH"
log_message "Warning free space threshold: $WARNING_THRESHOLD%"
log_message "Critical free space threshold: $CRITICAL_THRESHOLD%"
log_message "Command to be executed: $CMD"

# Pre-flight disk space check
log_message "Performing pre-flight disk space check..."
if ! /usr/local/bin/disk-health-check.sh -p "$DISK_CHECK_PATH" -w "$WARNING_THRESHOLD" -c "$CRITICAL_THRESHOLD"; then
    log_message "ERROR: Pre-flight disk space check failed. Aborting SSTable upgrade to prevent disk space issues."
    exit 1
fi
log_message "Disk space OK. Proceeding with SSTable upgrade."

# Execute the command
if $CMD; then
    log_message "--- SSTable Upgrade Finished Successfully ---"
    exit 0
else
    UPGRADE_EXIT_CODE=$?
    log_message "ERROR: SSTable upgrade command failed with exit code $UPGRADE_EXIT_CODE."
    exit $UPGRADE_EXIT_CODE
fi
`,
      'compaction-manager.sh': `#!/bin/bash
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
`,
      'cassandra_range_repair.py': '#!/usr/bin/env python3\\nprint("Cassandra Range Repair Python Script")',
      'range-repair.sh': '#!/bin/bash\\necho "Range Repair Script"',
};
