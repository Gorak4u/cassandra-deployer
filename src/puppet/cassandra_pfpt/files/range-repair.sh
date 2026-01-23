#!/bin/bash
set -euo pipefail

DISK_CHECK_PATH="/var/lib/cassandra/data"
WARNING_THRESHOLD=75
CRITICAL_THRESHOLD=85
LOG_FILE="/var/log/cassandra/repair.log"
LOCK_FILE="/var/run/cassandra_repair.lock"
KEYSPACE="${1:-}" # Optional: specify a keyspace

# The new python script will log to stdout, which will be captured by systemd's journal.
# We will still use this log file for the shell wrapper's messages.
log_message() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# --- Lock File Management ---
if [ -f "$LOCK_FILE" ]; then
    OLD_PID=$(cat "$LOCK_FILE")
    if ps -p "$OLD_PID" > /dev/null; then
        log_message "Repair process with PID $OLD_PID is still running. Skipping this scheduled run."
        exit 0
    else
        log_message "Found stale lock file for dead PID $OLD_PID. Removing and proceeding."
        rm -f "$LOCK_FILE"
    fi
fi

# Create lock file and set trap to remove it on exit
echo $$ > "$LOCK_FILE"
trap 'rm -f "$LOCK_FILE"' EXIT

log_message "--- Starting Granular Repair Manager ---"
log_message "Lock file created at $LOCK_FILE with PID $$."

# The python script takes the keyspace as an optional argument.
# If a keyspace is provided to this shell script, it will be passed along.
PYTHON_CMD="/usr/local/bin/cassandra_range_repair.py"
if [ -n "$KEYSPACE" ]; then
    log_message "Targeting keyspace: $KEYSPACE"
    PYTHON_CMD+=" $KEYSPACE"
else
    log_message "Targeting all non-system keyspaces."
fi

# Pre-flight disk space check
log_message "Performing pre-flight disk usage check..."
if ! /usr/local/bin/disk-health-check.sh -p "$DISK_CHECK_PATH" -w "$WARNING_THRESHOLD" -c "$CRITICAL_THRESHOLD"; then
    log_message "ERROR: Pre-flight disk usage check failed. Aborting repair to prevent disk space issues."
    exit 1 # trap will remove the lock file
fi
log_message "Disk usage OK. Proceeding with repair."

# Execute repair via python script
log_message "Executing command: $PYTHON_CMD"
# The python script's logging goes to stdout, which journald will capture.
if $PYTHON_CMD; then
    log_message "--- Granular Repair Finished Successfully ---"
    # trap will remove the lock file
    exit 0
else
    REPAIR_EXIT_CODE=$?
    log_message "ERROR: Granular repair script failed with exit code $REPAIR_EXIT_CODE. See journalctl -u cassandra-repair.service for details."
    # trap will remove the lock file
    exit $REPAIR_EXIT_CODE
fi
