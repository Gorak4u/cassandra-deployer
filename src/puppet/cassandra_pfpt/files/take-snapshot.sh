#!/bin/bash
# A simple wrapper script to take a snapshot with a generated tag.

set -euo pipefail

SNAPSHOT_TAG="adhoc_$(date +%Y%m%d_%H%M%S)"
KEYSPACES="${1:-}" # Optional: comma-separated list of keyspaces

echo "Starting snapshot with tag: ${SNAPSHOT_TAG}"

CMD="nodetool snapshot -t ${SNAPSHOT_TAG}"

if [ -n "$KEYSPACES" ]; then
    echo "Targeting keyspaces: $KEYSPACES"
    # Convert comma-separated to space-separated for the command
    CMD+=" -- $(echo $KEYSPACES | sed 's/,/ /g')"
fi

if ${CMD}; then
    echo "Snapshot taken successfully."
    echo "To clear this snapshot, run: nodetool clearsnapshot -t ${SNAPSHOT_TAG}"
else
    echo "ERROR: Failed to take snapshot."
    exit 1
fi

exit 0
