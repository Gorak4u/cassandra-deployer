
export const maintenanceScripts = {
      'cassandra-upgrade-precheck.sh': `#!/bin/bash
set -euo pipefail

log_message() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] \$1"
}

log_message "--- Starting Cassandra Upgrade Pre-check ---"
FAILED=false

# 1. Check for schema agreement
log_message "Checking for schema agreement..."
if ! nodetool describecluster | grep "Schema versions:" | awk '{print \$NF}' | grep -qE '^[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}$'; then
    log_message "ERROR: Not all nodes agree on schema version. Do not upgrade."
    FAILED=true
else
    log_message "OK: All nodes agree on schema version."
fi

# 2. Check if all nodes are UP and NORMAL
log_message "Checking node statuses..."
if nodetool status | grep -v '^UN ' | grep -q ' U[LJM] '; then
    log_message "ERROR: Not all nodes are in the UN (Up/Normal) state. Do not upgrade."
    nodetool status | grep -v '^UN '
    FAILED=true
else
    log_message "OK: All nodes are in UN state."
fi

# 3. Check for any streaming operations
log_message "Checking for streaming operations..."
if ! nodetool netstats | grep -q "Not sending any streams"; then
    log_message "ERROR: Node is currently streaming data. Wait for it to complete before upgrading."
    FAILED=true
else
    log_message "OK: No streaming operations in progress."
fi

# 4. Check for hints
log_message "Checking for pending hints..."
HINTS_PENDING=$(nodetool tpstats | grep "HintedHandoff" | awk '{print \$5}')
if [[ "\$HINTS_PENDING" -gt 0 ]]; then
    log_message "WARNING: There are \$HINTS_PENDING pending hints. It is recommended to wait for them to clear."
    # This might not be a hard failure depending on policy
else
    log_message "OK: No pending hints."
fi

# 5. Check if drain is possible
log_message "Attempting to drain the node..."
if ! nodetool drain; then
    log_message "ERROR: Failed to drain the node. This is a critical step before upgrade. Do not proceed."
    FAILED=true
else
    log_message "SUCCESS: Node drained successfully. It is now ready for the service to be stopped and the package to be upgraded."
fi


if [ "\$FAILED" = true ]; then
    log_message "--- Upgrade Pre-check FAILED. Do not proceed with the upgrade. ---"
    exit 1
else
    log_message "--- Upgrade Pre-check PASSED. You can now stop the service and upgrade the Cassandra package. ---"
    exit 0
fi
`,
      'repair-node.sh': `#!/bin/bash
nodetool repair -pr`,
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
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] \$1" | tee -a "\$LOG_FILE"
}

# --- Usage ---
usage() {
    log_message "Usage: $0 [OPTIONS]"
    log_message "Safely runs 'nodetool cleanup' with pre-flight disk space checks."
    log_message "  -k, --keyspace <name>       Specify the keyspace. Required if specifying tables."
    log_message "  -t, --table <name>          Specify a table to clean up. Can be used multiple times."
    log_message "  -j, --jobs <num>            Number of concurrent sstable cleanup jobs. Default: 0 (auto)"
    log_message "  -d, --disk-path <path>      Path to monitor for disk space. Default: \$DISK_CHECK_PATH"
    log_message "  -w, --warning <%>           Warning free space threshold (%). Aborts if below. Default: \$WARNING_THRESHOLD"
    log_message "  -c, --critical <%>          Critical free space threshold (%). Aborts if below. Default: \$CRITICAL_THRESHOLD"
    log_message "  -h, --help                  Show this help message."
    exit 1
}

# --- Argument Parsing ---
while [[ "\$#" -gt 0 ]]; do
    case \$1 in
        -k|--keyspace) KEYSPACE="\$2"; shift ;;
        -t|--table) TABLE_LIST="\$TABLE_LIST \$2"; shift ;;
        -j|--jobs) JOBS="\$2"; shift ;;
        -d|--disk-path) DISK_CHECK_PATH="\$2"; shift ;;
        -w|--warning) WARNING_THRESHOLD="\$2"; shift ;;
        -c|--critical) CRITICAL_THRESHOLD="\$2"; shift ;;
        -h|--help) usage ;;
        *) log_message "Unknown parameter passed: \$1"; usage ;;
    esac
    shift
done

if [[ -n "\$TABLE_LIST" && -z "\$KEYSPACE" ]]; then
    log_message "ERROR: A keyspace (-k) must be specified when cleaning up specific tables (-t)."
    exit 1
fi

# --- Main Logic ---
log_message "--- Starting Nodetool Cleanup Manager ---"

# Build the nodetool command
CMD="nodetool cleanup"
TARGET_DESC="full node"

# Add options
if [[ \$JOBS -gt 0 ]]; then
    CMD+=" -j \$JOBS"
fi

# Add keyspace/table arguments
if [[ -n "\$KEYSPACE" ]]; then
    TARGET_DESC="keyspace '\$KEYSPACE'"
    CMD+=" -- \$KEYSPACE"
    if [[ -n "\$TABLE_LIST" ]]; then
        CMD+=\$TABLE_LIST
        CLEAN_TABLE_LIST=$(echo "\$TABLE_LIST" | sed 's/^ *//g')
        TARGET_DESC="table(s) '\$CLEAN_TABLE_LIST' in keyspace '\$KEYSPACE'"
    fi
fi

log_message "Target: \$TARGET_DESC"
log_message "Disk path to check: \$DISK_CHECK_PATH"
log_message "Warning free space threshold: \$WARNING_THRESHOLD%"
log_message "Critical free space threshold: \$CRITICAL_THRESHOLD%"
log_message "Command to be executed: \$CMD"

# Pre-flight disk space check
log_message "Performing pre-flight disk space check..."
if ! /usr/local/bin/disk-health-check.sh -p "\$DISK_CHECK_PATH" -w "\$WARNING_THRESHOLD" -c "\$CRITICAL_THRESHOLD"; then
    log_message "ERROR: Pre-flight disk space check failed. Aborting cleanup to prevent disk space issues."
    exit 1
fi
log_message "Disk space OK. Proceeding with cleanup."

# Execute the command
if \$CMD; then
    log_message "--- Nodetool Cleanup Finished Successfully ---"
    exit 0
else
    CLEANUP_EXIT_CODE=\$?
    log_message "ERROR: Nodetool cleanup command failed with exit code \$CLEANUP_EXIT_CODE."
    exit \$CLEANUP_EXIT_CODE
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
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] \$1" | tee -a "\$LOG_FILE"
}

# --- Usage ---
usage() {
    log_message "Usage: $0 [OPTIONS]"
    log_message "Safely runs 'nodetool garbagecollect' with pre-flight disk space checks."
    log_message "  -k, --keyspace <name>       Specify the keyspace. Required if specifying tables."
    log_message "  -t, --table <name>          Specify a table to collect. Can be used multiple times."
    log_message "  -g, --granularity <CELL|ROW> Granularity of tombstones to remove. Default: ROW"
    log_message "  -j, --jobs <num>            Number of concurrent sstable garbage collection jobs. Default: 0 (auto)"
    log_message "  -d, --disk-path <path>      Path to monitor for disk space. Default: \$DISK_CHECK_PATH"
    log_message "  -w, --warning <%>           Warning free space threshold (%). Aborts if below. Default: \$WARNING_THRESHOLD"
    log_message "  -c, --critical <%>          Critical free space threshold (%). Aborts if below. Default: \$CRITICAL_THRESHOLD"
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
while [[ "\$#" -gt 0 ]]; do
    case \$1 in
        -k|--keyspace) KEYSPACE="\$2"; shift ;;
        -t|--table) TABLE_LIST="\$TABLE_LIST \$2"; shift ;;
        -g|--granularity) GRANULARITY="\$2"; shift ;;
        -j|--jobs) JOBS="\$2"; shift ;;
        -d|--disk-path) DISK_CHECK_PATH="\$2"; shift ;;
        -w|--warning) WARNING_THRESHOLD="\$2"; shift ;;
        -c|--critical) CRITICAL_THRESHOLD="\$2"; shift ;;
        -h|--help) usage ;;
        *) log_message "Unknown parameter passed: \$1"; usage ;;
    esac
    shift
done

if [[ -n "\$TABLE_LIST" && -z "\$KEYSPACE" ]]; then
    log_message "ERROR: A keyspace (-k) must be specified when collecting on specific tables (-t)."
    exit 1
fi

# --- Main Logic ---
log_message "--- Starting Garbage Collect Manager ---"

# Build the nodetool command
CMD="nodetool garbagecollect"
TARGET_DESC="full node"

# Add options
CMD+=" -g \$GRANULARITY"
if [[ \$JOBS -gt 0 ]]; then
    CMD+=" -j \$JOBS"
fi

# Add keyspace/table arguments
if [[ -n "\$KEYSPACE" ]]; then
    TARGET_DESC="keyspace '\$KEYSPACE'"
    CMD+=" -- \$KEYSPACE"
    if [[ -n "\$TABLE_LIST" ]]; then
        CMD+=\$TABLE_LIST
        # Remove leading space for description
        CLEAN_TABLE_LIST=$(echo "\$TABLE_LIST" | sed 's/^ *//g')
        TARGET_DESC="table(s) '\$CLEAN_TABLE_LIST' in keyspace '\$KEYSPACE'"
    fi
fi

log_message "Target: \$TARGET_DESC"
log_message "Disk path to check: \$DISK_CHECK_PATH"
log_message "Warning free space threshold: \$WARNING_THRESHOLD%"
log_message "Critical free space threshold: \$CRITICAL_THRESHOLD%"
log_message "Command to be executed: \$CMD"

# Pre-flight disk space check
log_message "Performing pre-flight disk space check..."
if ! /usr/local/bin/disk-health-check.sh -p "\$DISK_CHECK_PATH" -w "\$WARNING_THRESHOLD" -c "\$CRITICAL_THRESHOLD"; then
    log_message "ERROR: Pre-flight disk space check failed. Aborting garbage collection to prevent disk space issues."
    exit 1
fi
log_message "Disk space OK. Proceeding with garbage collection."

# Execute the command
if \$CMD; then
    log_message "--- Garbage Collect Finished Successfully ---"
    exit 0
else
    GC_EXIT_CODE=\$?
    log_message "ERROR: Garbage collection command failed with exit code \$GC_EXIT_CODE."
    exit \$GC_EXIT_CODE
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
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] \$1" | tee -a "\$LOG_FILE"
}

# --- Usage ---
usage() {
    log_message "Usage: $0 [OPTIONS]"
    log_message "Safely runs 'nodetool upgradesstables' with pre-flight disk space checks."
    log_message "This is typically run after a major version upgrade of Cassandra."
    log_message "  -k, --keyspace <name>       Specify the keyspace. Required if specifying tables."
    log_message "  -t, --table <name>          Specify a table to upgrade. Can be used multiple times."
    log_message "  -j, --jobs <num>            Number of concurrent sstable upgrade jobs. Default: 0 (auto)"
    log_message "  -d, --disk-path <path>      Path to monitor for disk space. Default: \$DISK_CHECK_PATH"
    log_message "  -w, --warning <%>           Warning free space threshold (%). Aborts if below. Default: \$WARNING_THRESHOLD"
    log_message "  -c, --critical <%>          Critical free space threshold (%). Aborts if below. Default: \$CRITICAL_THRESHOLD"
    log_message "  -h, --help                  Show this help message."
    exit 1
}

# --- Argument Parsing ---
while [[ "\$#" -gt 0 ]]; do
    case \$1 in
        -k|--keyspace) KEYSPACE="\$2"; shift ;;
        -t|--table) TABLE_LIST="\$TABLE_LIST \$2"; shift ;;
        -j|--jobs) JOBS="\$2"; shift ;;
        -d|--disk-path) DISK_CHECK_PATH="\$2"; shift ;;
        -w|--warning) WARNING_THRESHOLD="\$2"; shift ;;
        -c|--critical) CRITICAL_THRESHOLD="\$2"; shift ;;
        -h|--help) usage ;;
        *) log_message "Unknown parameter passed: \$1"; usage ;;
    esac
    shift
done

if [[ -n "\$TABLE_LIST" && -z "\$KEYSPACE" ]]; then
    log_message "ERROR: A keyspace (-k) must be specified when upgrading specific tables (-t)."
    exit 1
fi

# --- Main Logic ---
log_message "--- Starting SSTable Upgrade Manager ---"

# Build the nodetool command
CMD="nodetool upgradesstables"
TARGET_DESC="all keyspaces and tables"

# Add options
if [[ \$JOBS -gt 0 ]]; then
    CMD+=" -j \$JOBS"
fi

# Add keyspace/table arguments
if [[ -n "\$KEYSPACE" ]]; then
    TARGET_DESC="keyspace '\$KEYSPACE'"
    CMD+=" -- \$KEYSPACE"
    if [[ -n "\$TABLE_LIST" ]]; then
        CMD+=\$TABLE_LIST
        CLEAN_TABLE_LIST=$(echo "\$TABLE_LIST" | sed 's/^ *//g')
        TARGET_DESC="table(s) '\$CLEAN_TABLE_LIST' in keyspace '\$KEYSPACE'"
    fi
else
    # If no keyspace is provided, nodetool upgrades all sstables. The -a flag is implied.
    CMD+=" -a"
fi

log_message "Target: \$TARGET_DESC"
log_message "Disk path to check: \$DISK_CHECK_PATH"
log_message "Warning free space threshold: \$WARNING_THRESHOLD%"
log_message "Critical free space threshold: \$CRITICAL_THRESHOLD%"
log_message "Command to be executed: \$CMD"

# Pre-flight disk space check
log_message "Performing pre-flight disk space check..."
if ! /usr/local/bin/disk-health-check.sh -p "\$DISK_CHECK_PATH" -w "\$WARNING_THRESHOLD" -c "\$CRITICAL_THRESHOLD"; then
    log_message "ERROR: Pre-flight disk space check failed. Aborting SSTable upgrade to prevent disk space issues."
    exit 1
fi
log_message "Disk space OK. Proceeding with SSTable upgrade."

# Execute the command
if \$CMD; then
    log_message "--- SSTable Upgrade Finished Successfully ---"
    exit 0
else
    UPGRADE_EXIT_CODE=\$?
    log_message "ERROR: SSTable upgrade command failed with exit code \$UPGRADE_EXIT_CODE."
    exit \$UPGRADE_EXIT_CODE
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
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] \$1" | tee -a "\$LOG_FILE"
}

# --- Usage ---
usage() {
    log_message "Usage: $0 [OPTIONS]"
    log_message "Manages Cassandra compaction with disk space monitoring."
    log_message "  -k, --keyspace <name>    Specify the keyspace to compact. (Required for -t)"
    log_message "  -t, --table <name>       Specify the table to compact."
    log_message "  -d, --disk-path <path>   Path to monitor for disk space. Default: \$DISK_CHECK_PATH"
    log_message "  -c, --critical <%>       Critical free space threshold (%). Aborts if below. Default: \$CRITICAL_THRESHOLD"
    log_message "  -i, --interval <sec>     Interval in seconds to check disk space. Default: \$CHECK_INTERVAL"
    log_message "  -h, --help               Show this help message."
    log_message ""
    log_message "Examples:"
    log_message "  Full node compaction:       $0"
    log_message "  Keyspace compaction:        $0 -k my_keyspace"
    log_message "  Table compaction:           $0 -k my_keyspace -t my_table"
    exit 1
}

# --- Argument Parsing ---
while [[ "\$#" -gt 0 ]]; do
    case \$1 in
        -k|--keyspace) KEYSPACE="\$2"; shift ;;
        -t|--table) TABLE="\$2"; shift ;;
        -d|--disk-path) DISK_CHECK_PATH="\$2"; shift ;;
        -c|--critical) CRITICAL_THRESHOLD="\$2"; shift ;;
        -i|--interval) CHECK_INTERVAL="\$2"; shift ;;
        -h|--help) usage ;;
        *) log_message "Unknown parameter passed: \$1"; usage ;;
    esac
    shift
done

if [[ -n "\$TABLE" && -z "\$KEYSPACE" ]]; then
    log_message "ERROR: A keyspace (-k) must be specified when compacting a table (-t)."
    exit 1
fi

# --- Main Logic ---
log_message "--- Starting Compaction Manager ---"

# Build the nodetool command
CMD="nodetool compact"
TARGET_DESC="full node"
if [[ -n "\$KEYSPACE" ]]; then
    CMD+=" \$KEYSPACE"
    TARGET_DESC="keyspace '\$KEYSPACE'"
    if [[ -n "\$TABLE" ]]; then
        CMD+=" \$TABLE"
        TARGET_DESC="table '\$TABLE'"
    fi
fi

log_message "Target: \$TARGET_DESC"
log_message "Disk path to monitor: \$DISK_CHECK_PATH"
log_message "Critical free space threshold: \$CRITICAL_THRESHOLD%"
log_message "Disk check interval: \$CHECK_INTERVALs"

# Start compaction in the background
log_message "Starting compaction process..."
\$CMD &
COMPACTION_PID=\$!
log_message "Compaction started with PID: \$COMPACTION_PID"

# Monitor the process
while ps -p \$COMPACTION_PID > /dev/null; do
    log_message "Compaction running (PID: \$COMPACTION_PID). Checking disk space..."
    
    # Use the existing health check script
    if ! /usr/local/bin/disk-health-check.sh -p "\$DISK_CHECK_PATH" -c "\$CRITICAL_THRESHOLD"; then
        log_message "CRITICAL: Disk space threshold reached. Stopping compaction."
        nodetool stop COMPACTION
        # Wait a moment for the stop command to be processed
        sleep 10
        # Check if the process is still running, if so, kill it forcefully
        if ps -p \$COMPACTION_PID > /dev/null; then
             log_message "Nodetool stop did not terminate process. Sending KILL signal to PID \$COMPACTION_PID."
             kill -9 \$COMPACTION_PID
        fi
        log_message "ERROR: Compaction aborted due to low disk space."
        exit 2
    fi

    log_message "Disk space OK. Sleeping for \$CHECK_INTERVAL seconds."
    sleep \$CHECK_INTERVAL
done

wait \$COMPACTION_PID
COMPACTION_EXIT_CODE=\$?

if [[ \$COMPACTION_EXIT_CODE -eq 0 ]]; then
    log_message "--- Compaction Manager Finished Successfully ---"
    exit 0
else
    # This handles cases where compaction fails for reasons other than disk space
    log_message "ERROR: Compaction process (PID: \$COMPACTION_PID) exited with non-zero status: \$COMPACTION_EXIT_CODE."
    exit \$COMPACTION_EXIT_CODE
fi
`,
      'cassandra_range_repair.py': `#!/usr/bin/env python3
import subprocess
import sys
import argparse

def run_repair(keyspace, full=False):
    """
    Runs nodetool repair on a given keyspace.
    By default, it runs a primary range repair (-pr).
    """
    if full:
        repair_type = "full"
        command = f"nodetool repair {keyspace}"
    else:
        repair_type = "primary range"
        command = f"nodetool repair -pr {keyspace}"

    print(f"--- Starting {repair_type} repair for keyspace '{keyspace}' ---")
    print(f"Executing command: {command}")

    try:
        # Use Popen to stream output in real time
        process = subprocess.Popen(
            command.split(),
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1
        )

        # Read and print output line by line
        for line in iter(process.stdout.readline, ''):
            print(line, end='')

        process.stdout.close()
        return_code = process.wait()

        if return_code == 0:
            print(f"--- Repair for keyspace '{keyspace}' completed successfully. ---")
        else:
            print(f"--- ERROR: Repair for keyspace '{keyspace}' failed with exit code {return_code}. ---", file=sys.stderr)
        
        return return_code

    except FileNotFoundError:
        print("ERROR: 'nodetool' command not found. Is Cassandra installed and in your PATH?", file=sys.stderr)
        return 1
    except Exception as e:
        print(f"An unexpected error occurred: {e}", file=sys.stderr)
        return 1

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description="A wrapper script for running Cassandra's nodetool repair.")
    parser.add_argument('keyspace', help='The name of the keyspace to repair.')
    parser.add_argument('--full', action='store_true', help='Perform a full repair instead of a primary range repair.')
    
    args = parser.parse_args()
    
    exit_code = run_repair(args.keyspace, args.full)
    sys.exit(exit_code)
`,
      'range-repair.sh': `#!/bin/bash
set -euo pipefail

# This script runs a primary-range repair on the local node.
# It includes a pre-flight disk space check.

DISK_CHECK_PATH="/var/lib/cassandra/data"
WARNING_THRESHOLD=25
CRITICAL_THRESHOLD=15
LOG_FILE="/var/log/cassandra/repair.log"

log_message() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] \$1" | tee -a "\$LOG_FILE"
}

log_message "--- Starting Primary Range Repair ---"
log_message "This will repair the primary token ranges this node is responsible for."

# Pre-flight disk space check
log_message "Performing pre-flight disk space check..."
if ! /usr/local/bin/disk-health-check.sh -p "\$DISK_CHECK_PATH" -w "\$WARNING_THRESHOLD" -c "\$CRITICAL_THRESHOLD"; then
    log_message "ERROR: Pre-flight disk space check failed. Aborting repair to prevent disk space issues."
    exit 1
fi
log_message "Disk space OK. Proceeding with repair."

# Execute repair
if nodetool repair -pr; then
    log_message "--- Primary Range Repair Finished Successfully ---"
    exit 0
else
    REPAIR_EXIT_CODE=\$?
    log_message "ERROR: Nodetool repair failed with exit code \$REPAIR_EXIT_CODE."
    exit \$REPAIR_EXIT_CODE
fi
`,
};

    