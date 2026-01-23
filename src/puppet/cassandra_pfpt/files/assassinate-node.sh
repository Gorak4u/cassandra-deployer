#!/bin/bash
# Assassinate a node. Use with extreme caution.

# --- Color Codes ---
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

log_message() {
  echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

NODE_IP="$1"

if [ -z "$NODE_IP" ]; then
  log_message "${RED}Error: Node IP address must be provided as an argument.${NC}"
  log_message "Usage: $0 <ip_address_of_dead_node>"
  exit 1
fi

log_message "${YELLOW}WARNING: Attempting to assassinate node at IP: $NODE_IP. This will remove it from the cluster.${NC}"
log_message "${YELLOW}Are you sure you want to proceed? Type 'yes' to confirm.${NC}"
read confirmation

if [ "$confirmation" != "yes" ]; then
  log_message "Aborted."
  exit 0
fi

nodetool assassinate "$NODE_IP"
ASSASSINATE_STATUS=$?

if [ $ASSASSINATE_STATUS -eq 0 ]; then
  log_message "${GREEN}Nodetool assassinate of $NODE_IP completed successfully.${NC}"
  exit 0
else
  log_message "${RED}Nodetool assassinate of $NODE_IP FAILED with exit code $ASSASSINATE_STATUS.${NC}"
  exit 1
fi
