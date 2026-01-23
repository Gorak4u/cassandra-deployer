#!/bin/bash
set -e

# --- Color Codes ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_message() {
  echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

log_ok() {
  log_message "${GREEN}OK: $1${NC}"
}

log_error() {
  log_message "${RED}ERROR: $1${NC}"
  exit 1
}

log_warning() {
  log_message "${YELLOW}WARNING: $1${NC}"
}

log_message "${BLUE}--- Starting Node Health Check ---${NC}"
LOCAL_IP=$(hostname -i)

# 1. Disk Space Check
log_message "${BLUE}1. Checking disk space...${NC}"
if ! /usr/local/bin/disk-health-check.sh; then
    log_error "Disk space check failed. See output from disk-health-check.sh."
else
    log_ok "Disk space is sufficient."
fi

# 2. Node Status Check
log_message "${BLUE}2. Checking local node status...${NC}"
NODE_STATUS=$(nodetool status | grep "$LOCAL_IP" | awk '{print $1}')

if [ "$NODE_STATUS" == "UN" ]; then
    log_ok "Node status is UN (Up/Normal)."
elif [ -z "$NODE_STATUS" ]; then
    log_error "Could not find local node IP ($LOCAL_IP) in nodetool status output."
else
    log_error "Node status is '$NODE_STATUS', not UN."
fi

# 3. Gossip Check
log_message "${BLUE}3. Checking gossip status...${NC}"
GOSSIP_STATUS=$(nodetool gossipinfo | grep "STATUS" | grep "$LOCAL_IP" | cut -d':' -f2)
if [[ "$GOSSIP_STATUS" == "NORMAL" ]]; then
    log_ok "Gossip state is NORMAL."
else
    log_warning "Gossip state is '$GOSSIP_STATUS', not NORMAL. This might be temporary."
fi

# 4. Check for active streams
log_message "${BLUE}4. Checking for network streams...${NC}"
if ! nodetool netstats | grep -q "Mode: NORMAL"; then
    log_warning "Node is not in NORMAL mode. It might be streaming, joining, or leaving."
    nodetool netstats
else
    log_ok "Network mode is NORMAL."
fi

# 5. Check for exceptions in the log
log_message "${BLUE}5. Scanning system log for recent exceptions...${NC}"
if journalctl -u cassandra -S "10 minutes ago" | grep -q "Exception"; then
    log_warning "Found 'Exception' in Cassandra logs from the last 10 minutes. Please review logs manually."
    journalctl -u cassandra -S "10 minutes ago" | grep "Exception" | tail -n 10
else
    log_ok "No recent exceptions found in logs."
fi

log_message "${GREEN}--- Node Health Check Completed ---${NC}"
