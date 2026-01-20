#!/bin/bash
set -euo pipefail

# This script creates a local, verified snapshot for ad-hoc backups or testing.
# It does NOT upload to S3 or clean up automatically.

KEYSPACES="${1:-}" # Optional: comma-separated list of keyspaces
SNAPSHOT_TAG="adhoc_snapshot_$(date +%Y%m%d%H%M%S)"
BACKUP_DIR="/var/lib/cassandra/data"
LOG_FILE="/var/log/cassandra/robust_backup.log"

log_message() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log_message "--- Starting Robust Local Snapshot ---"
log_message "Snapshot Tag: $SNAPSHOT_TAG"

# Build command
CMD="nodetool snapshot -t $SNAPSHOT_TAG"
if [ -n "$KEYSPACES" ]; then
    log_message "Targeting keyspaces: $KEYSPACES"
    # Convert comma-separated to space-separated for the command
    CMD+=" -- $(echo $KEYSPACES | sed 's/,/ /g')"
fi

# 1. Take snapshot
log_message "Executing: $CMD"
if ! $CMD; then
    log_message "ERROR: Failed to take snapshot. Aborting."
    exit 1
fi
log_message "Snapshot created successfully."

# 2. Verify snapshot
log_message "Verifying snapshot files..."
SNAPSHOT_PATH_COUNT=$(find "$BACKUP_DIR" -type d -path "*/snapshots/$SNAPSHOT_TAG" | wc -l)

if [ "$SNAPSHOT_PATH_COUNT" -eq 0 ]; then
    log_message "WARNING: No snapshot directories found. This may be expected if the targeted keyspaces have no data."
else
    log_message "Found $SNAPSHOT_PATH_COUNT snapshot directories. Checking for content..."
    # A simple verification: check that there are SSTable files in the snapshot dirs
    SSTABLE_COUNT=$(find "$BACKUP_DIR" -type f -path "*/snapshots/$SNAPSHOT_TAG/*" -name "*.db" | wc -l)
    if [ "$SSTABLE_COUNT" -gt 0 ]; then
        log_message "OK: Found $SSTABLE_COUNT SSTable files. Snapshot appears valid."
    else
        log_message "WARNING: No SSTable (.db) files found in snapshot directories. The snapshot might be empty."
    fi
fi

log_message "--- Robust Local Snapshot Finished ---"
log_message "Snapshot tag '$SNAPSHOT_TAG' is available on disk."
log_message "To clear this snapshot, run: nodetool clearsnapshot -t $SNAPSHOT_TAG"
exit 0
