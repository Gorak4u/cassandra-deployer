#!/bin/bash
set -euo pipefail

# --- Color Codes ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

LOG_FILE="/var/log/cassandra/stop-node.log"

log_message() {
  echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log_message "${BLUE}--- Starting Safe Stop of Cassandra Node ---${NC}"
log_message "${YELLOW}This will drain the node and then stop the service.${NC}"

read -p "Are you sure you want to proceed? Type 'yes': " confirmation
if [[ "$confirmation" != "yes" ]]; then
    log_message "Aborted by user."
    exit 0
fi

# 1. Drain the node
log_message "${BLUE}Step 1: Draining node...${NC}"
if ! nodetool drain; then
    log_message "${RED}ERROR: Failed to drain the node. Aborting stop.${NC}"
    exit 1
fi
log_message "${GREEN}Node drained successfully.${NC}"

# 2. Stop the service
log_message "${BLUE}Step 2: Stopping the cassandra service...${NC}"
if ! systemctl stop cassandra; then
    log_message "${RED}ERROR: Failed to stop the cassandra service. Please check 'systemctl status cassandra'.${NC}"
    exit 1
fi
log_message "${GREEN}Service stopped successfully.${NC}"
log_message "${GREEN}--- Node Stop Finished ---${NC}"
exit 0
