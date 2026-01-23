#!/bin/bash
# Drains a node.

# --- Color Codes ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_message() {
  echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

log_message "${BLUE}Starting nodetool drain...${NC}"
nodetool drain
DRAIN_STATUS=$?

if [ $DRAIN_STATUS -eq 0 ]; then
  log_message "${GREEN}Nodetool drain completed successfully.${NC}"
  # Wait a bit and check status (optional)
  sleep 5
  NODETOOL_STATUS=$(nodetool status)
  if echo "$NODETOOL_STATUS" | grep -q "$(hostname -I | awk '{print $1}')" | grep -q 'DN'; then
    log_message "${GREEN}Node is in Drained (DN) state.${NC}"
  else
    log_message "${YELLOW}Node is not in Drained (DN) state after drain command.${NC}"
  fi
  exit 0
else
  log_message "${RED}Nodetool drain FAILED with exit code $DRAIN_STATUS.${NC}"
  exit 1
fi
