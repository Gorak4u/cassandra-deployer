#!/bin/bash
set -euo pipefail

SNAPSHOT_TAG="${1:-snapshot_$(date +%Y%m%d%H%M%S)}"
KEYSPACES="${2:-}" # Optional: comma-separated list of keyspaces

log_message() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

log_message "--- Taking Cassandra Snapshot ---"
log_message "Snapshot Tag: $SNAPSHOT_TAG"

CMD="nodetool snapshot -t $SNAPSHOT_TAG"

if [ -n "$KEYSPACES" ]; then
    log_message "Targeting keyspaces: $KEYSPACES"
    # Convert comma-separated to space-separated
    CMD+=" -- $(echo $KEYSPACES | sed 's/,/ /g')"
fi

log_message "Executing: $CMD"
if $CMD; then
    log_message "SUCCESS: Snapshot '$SNAPSHOT_TAG' created successfully."
    exit 0
else
    log_message "ERROR: Failed to create snapshot."
    exit 1
fi
