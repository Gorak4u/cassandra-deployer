#!/bin/bash
# This file is managed by Puppet.
set -euo pipefail

# --- Color Codes ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

LOG_FILE="/var/log/cassandra/rolling_restart.log"

log_message() {
  echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log_message "${BLUE}--- Starting Safe Rolling Restart of Cassandra Node ---${NC}"

# 1. Drain the node
log_message "${BLUE}Step 1: Draining node (flushing memtables and stopping listeners)...${NC}"
if ! nodetool drain; then
    log_message "${RED}ERROR: Failed to drain the node. Aborting restart.${NC}"
    exit 1
fi
log_message "${GREEN}Node drained successfully.${NC}"

# 2. Stop the service
log_message "${BLUE}Step 2: Stopping the cassandra service...${NC}"
if ! systemctl stop cassandra; then
    log_message "${RED}ERROR: Failed to stop the cassandra service. Please check 'systemctl status cassandra'.${NC}"
    exit 1
fi
log_message "${GREEN}Service stopped.${NC}"

# 3. Start the service
log_message "${BLUE}Step 3: Starting the cassandra service...${NC}"
if ! systemctl start cassandra; then
    log_message "${RED}ERROR: Failed to start the cassandra service. Please check 'systemctl status cassandra' and logs.${NC}"
    exit 1
fi
log_message "${BLUE}Service start command issued. Waiting for node to initialize...${NC}"

# 4. Wait for node to be UP and NORMAL
CASSANDRA_READY=false
for i in {1..30}; do # Wait up to 5 minutes (30 * 10 seconds)
    # Grep for this node's IP in status output, check for 'UN'
    if nodetool status | grep "$(hostname -i)" | grep -q 'UN'; then
        CASSANDRA_READY=true
        break
    fi
    log_message "${BLUE}Waiting for node to report UP/NORMAL... (attempt $i of 30)${NC}"
    sleep 10
done

if [ "$CASSANDRA_READY" = true ]; then
    log_message "${GREEN}SUCCESS: Node has rejoined the cluster successfully.${NC}"
    log_message "${GREEN}--- Rolling Restart Finished ---${NC}"
    exit 0
else
    log_message "${RED}ERROR: Node failed to return to UN state within 5 minutes. Please investigate.${NC}"
    exit 1
fi
