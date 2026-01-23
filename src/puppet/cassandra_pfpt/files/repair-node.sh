#!/bin/bash
# Wrapper script to safely initiate a node repair.
# This script is a placeholder and simply calls the more advanced range-repair.sh script.
# It can be expanded with more pre-flight checks if needed.

set -euo pipefail

LOG_FILE="/var/log/cassandra/repair.log"

log_message() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] (Wrapper) $1" | tee -a "$LOG_FILE"
}

log_message "--- Delegating to Granular Repair Manager ---"

# Call the primary range-based repair script, passing all arguments
/usr/local/bin/range-repair.sh "$@"

exit $?
