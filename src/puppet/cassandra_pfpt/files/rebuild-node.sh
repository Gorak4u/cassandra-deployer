#!/bin/bash
set -euo pipefail

SOURCE_DC="$1"

# --- Color Codes ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_message() {
  echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

if [ -z "$SOURCE_DC" ]; then
    log_message "${RED}ERROR: Source datacenter must be provided as the first argument.${NC}"
    log_message "Usage: $0 <source_datacenter_name>"
    exit 1
fi

log_message "${BLUE}--- Starting Node Rebuild from DC: $SOURCE_DC ---${NC}"
log_message "${YELLOW}This will stream data from other replicas to this node.${NC}"
log_message "${YELLOW}Ensure this node is stopped, its data directory is empty, and it has started up again before running this.${NC}"
read -p "Are you sure you want to continue? Type 'yes': " confirmation
if [[ "$confirmation" != "yes" ]]; then
    log_message "Rebuild aborted by user."
    exit 0
fi

log_message "${BLUE}Starting nodetool rebuild...${NC}"
if nodetool rebuild -- "$SOURCE_DC"; then
    log_message "${GREEN}SUCCESS: Nodetool rebuild completed successfully.${NC}"
    exit 0
else
    REBUILD_STATUS=$?
    log_message "${RED}ERROR: Nodetool rebuild FAILED with exit code $REBUILD_STATUS.${NC}"
    exit $REBUILD_STATUS
fi
