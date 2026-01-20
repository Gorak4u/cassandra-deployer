#!/bin/bash
set -euo pipefail

SOURCE_DC="$1"

log_message() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

if [ -z "$SOURCE_DC" ]; then
    log_message "ERROR: Source datacenter must be provided as the first argument."
    log_message "Usage: $0 <source_datacenter_name>"
    exit 1
fi

log_message "--- Starting Node Rebuild from DC: $SOURCE_DC ---"
log_message "This will stream data from other replicas to this node."
log_message "Ensure this node is stopped, its data directory is empty, and it has started up again before running this."
read -p "Are you sure you want to continue? Type 'yes': " confirmation
if [[ "$confirmation" != "yes" ]]; then
    log_message "Rebuild aborted by user."
    exit 0
fi

log_message "Starting nodetool rebuild..."
if nodetool rebuild -- "$SOURCE_DC"; then
    log_message "SUCCESS: Nodetool rebuild completed successfully."
    exit 0
else
    REBUILD_STATUS=$?
    log_message "ERROR: Nodetool rebuild FAILED with exit code $REBUILD_STATUS."
    exit $REBUILD_STATUS
fi
