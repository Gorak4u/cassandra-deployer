#!/bin/bash
set -euo pipefail

DEAD_NODE_IP="$1"
JVM_OPTIONS_FILE="/etc/cassandra/conf/jvm-server.options"

log_message() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

if [ -z "$DEAD_NODE_IP" ]; then
    log_message "ERROR: IP address of the dead node to replace must be provided."
    log_message "Usage: $0 <ip_of_dead_node>"
    exit 1
fi

if [ ! -f "$JVM_OPTIONS_FILE" ]; then
    log_message "ERROR: JVM options file not found at $JVM_OPTIONS_FILE"
    exit 1
fi

log_message "--- Preparing Node for Replacement ---"
log_message "This script will configure this node to replace the dead node at IP: $DEAD_NODE_IP."
read -p "Are you sure? This should be run on a NEW, STOPPED node. Type 'yes': " confirmation
if [[ "$confirmation" != "yes" ]]; then
    log_message "Aborted by user."
    exit 0
fi

# Clean up any previous replacement flags
log_message "Removing any existing replace_address flags from $JVM_OPTIONS_FILE..."
sed -i '/-Dcassandra.replace_address/d' "$JVM_OPTIONS_FILE"

# Add the new flag
log_message "Adding replacement flag: -Dcassandra.replace_address_first_boot=$DEAD_NODE_IP"
echo "-Dcassandra.replace_address_first_boot=$DEAD_NODE_IP" >> "$JVM_OPTIONS_FILE"

log_message "SUCCESS: Node is configured for replacement."
log_message "You can now start the Cassandra service. It will bootstrap and replace the dead node."
exit 0
