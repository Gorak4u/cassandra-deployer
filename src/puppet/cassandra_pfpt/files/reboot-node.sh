#!/bin/bash
# This file is managed by Puppet.
set -euo pipefail

# --- Color Codes ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

LOG_FILE="/var/log/cassandra/reboot-node.log"

log_message() {
  echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log_message "${BLUE}--- Starting Safe Reboot of Machine ---${NC}"
log_message "${YELLOW}This will drain the Cassandra node and then reboot the entire machine.${NC}"
log_message "${YELLOW}This will cause a service interruption.${NC}"

read -p "Are you sure you want to proceed? Type 'yes': " confirmation
if [[ "$confirmation" != "yes" ]]; then
    log_message "Aborted by user."
    exit 0
fi

# 1. Drain the node
log_message "${BLUE}Step 1: Draining Cassandra node...${NC}"
if ! nodetool drain; then
    log_message "${RED}ERROR: Failed to drain the node. Aborting reboot.${NC}"
    exit 1
fi
log_message "${GREEN}Node drained successfully. Proceeding with reboot.${NC}"

# 2. Reboot the machine
log_message "${BLUE}Step 2: Issuing reboot command...${NC}"
reboot
