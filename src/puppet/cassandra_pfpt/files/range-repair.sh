#!/bin/bash
set -euo pipefail

# This script runs a primary-range repair on the local node.
# It includes a pre-flight disk space check.

DISK_CHECK_PATH="/var/lib/cassandra/data"
WARNING_THRESHOLD=25
CRITICAL_THRESHOLD=15
LOG_FILE="/var/log/cassandra/repair.log"

log_message() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log_message "--- Starting Primary Range Repair ---"
log_message "This will repair the primary token ranges this node is responsible for."

# Pre-flight disk space check
log_message "Performing pre-flight disk space check..."
if ! /usr/local/bin/disk-health-check.sh -p "$DISK_CHECK_PATH" -w "$WARNING_THRESHOLD" -c "$CRITICAL_THRESHOLD"; then
    log_message "ERROR: Pre-flight disk space check failed. Aborting repair to prevent disk space issues."
    exit 1
fi
log_message "Disk space OK. Proceeding with repair."

# Execute repair
if nodetool repair -pr; then
    log_message "--- Primary Range Repair Finished Successfully ---"
    exit 0
else
    REPAIR_EXIT_CODE=$?
    log_message "ERROR: Nodetool repair failed with exit code $REPAIR_EXIT_CODE."
    exit $REPAIR_EXIT_CODE
fi
