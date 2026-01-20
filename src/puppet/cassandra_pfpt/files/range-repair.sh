#!/bin/bash
set -euo pipefail

DISK_CHECK_PATH="/var/lib/cassandra/data"
WARNING_THRESHOLD=25
CRITICAL_THRESHOLD=15
LOG_FILE="/var/log/cassandra/repair.log"
KEYSPACE="${1:-}" # Optional: specify a keyspace

# The new python script will log to stdout, which will be captured by systemd's journal.
# We will still use this log file for the shell wrapper's messages.
log_message() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log_message "--- Starting Granular Repair Manager ---"

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
log_message "Performing pre-flight disk space check..."
if ! /usr/local/bin/disk-health-check.sh -p "$DISK_CHECK_PATH" -w "$WARNING_THRESHOLD" -c "$CRITICAL_THRESHOLD"; then
    log_message "ERROR: Pre-flight disk space check failed. Aborting repair to prevent disk space issues."
    exit 1
fi
log_message "Disk space OK. Proceeding with repair."

# Execute repair via python script
log_message "Executing command: $PYTHON_CMD"
# The python script's logging goes to stdout, which journald will capture.
if $PYTHON_CMD; then
    log_message "--- Granular Repair Finished Successfully ---"
    exit 0
else
    REPAIR_EXIT_CODE=$?
    log_message "ERROR: Granular repair script failed with exit code $REPAIR_EXIT_CODE. See journalctl -u cassandra-repair.service for details."
    exit $REPAIR_EXIT_CODE
fi
