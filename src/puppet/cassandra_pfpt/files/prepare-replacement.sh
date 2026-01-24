#!/bin/bash
# This file is managed by Puppet.
set -euo pipefail

DEAD_NODE_IP="$1"
JVM_OPTIONS_FILE="/etc/cassandra/conf/jvm-server.options"

# --- Color Codes ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_message() {
  echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

if [ -z "$DEAD_NODE_IP" ]; then
    log_message "${RED}ERROR: IP address of the dead node to replace must be provided.${NC}"
    log_message "Usage: $0 <ip_of_dead_node>"
    exit 1
fi

if [ ! -f "$JVM_OPTIONS_FILE" ]; then
    log_message "${RED}ERROR: JVM options file not found at $JVM_OPTIONS_FILE${NC}"
    exit 1
fi

log_message "${BLUE}--- Preparing Node for Replacement ---${NC}"
log_message "${YELLOW}This script will configure this node to replace the dead node at IP: $DEAD_NODE_IP.${NC}"
read -p "Are you sure? This should be run on a NEW, STOPPED node. Type 'yes': " confirmation
if [[ "$confirmation" != "yes" ]]; then
    log_message "Aborted by user."
    exit 0
fi

# Clean up any previous replacement flags
log_message "${BLUE}Removing any existing replace_address flags from $JVM_OPTIONS_FILE...${NC}"
sed -i '/-Dcassandra.replace_address/d' "$JVM_OPTIONS_FILE"

# Add the new flag
log_message "${BLUE}Adding replacement flag: -Dcassandra.replace_address_first_boot=$DEAD_NODE_IP${NC}"
echo "-Dcassandra.replace_address_first_boot=$DEAD_NODE_IP" >> "$JVM_OPTIONS_FILE"

log_message "${GREEN}SUCCESS: Node is configured for replacement.${NC}"
log_message "${GREEN}You can now start the Cassandra service. It will bootstrap and replace the dead node.${NC}"
exit 0
