#!/bin/bash
# A simple wrapper script to take a snapshot with a generated tag.

set -euo pipefail

# --- Color Codes ---
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

SNAPSHOT_TAG="adhoc_$(date +%Y%m%d_%H%M%S)"
KEYSPACES="${1:-}" # Optional: comma-separated list of keyspaces

echo -e "${BLUE}Starting snapshot with tag: ${SNAPSHOT_TAG}${NC}"

CMD="nodetool snapshot -t ${SNAPSHOT_TAG}"

if [ -n "$KEYSPACES" ]; then
    echo -e "${BLUE}Targeting keyspaces: $KEYSPACES${NC}"
    # Convert comma-separated to space-separated for the command
    CMD+=" -- $(echo $KEYSPACES | sed 's/,/ /g')"
fi

if ${CMD}; then
    echo -e "${GREEN}Snapshot taken successfully.${NC}"
    echo -e "${GREEN}To clear this snapshot, run: nodetool clearsnapshot -t ${SNAPSHOT_TAG}${NC}"
else
    echo -e "${RED}ERROR: Failed to take snapshot.${NC}"
    exit 1
fi

exit 0
