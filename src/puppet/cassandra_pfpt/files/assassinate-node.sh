#!/bin/bash
# Assassinate a node. Use with extreme caution.

log_message() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

NODE_IP="$1"

if [ -z "$NODE_IP" ]; then
  log_message "Error: Node IP address must be provided as an argument."
  log_message "Usage: $0 <ip_address_of_dead_node>"
  exit 1
fi

log_message "WARNING: Attempting to assassinate node at IP: $NODE_IP. This will remove it from the cluster."
log_message "Are you sure you want to proceed? Type 'yes' to confirm."
read confirmation

if [ "$confirmation" != "yes" ]; then
  log_message "Aborted."
  exit 0
fi

nodetool assassinate "$NODE_IP"
ASSASSINATE_STATUS=$?

if [ $ASSASSINATE_STATUS -eq 0 ]; then
  log_message "Nodetool assassinate of $NODE_IP completed successfully."
  exit 0
else
  log_message "Nodetool assassinate of $NODE_IP FAILED with exit code $ASSASSINATE_STATUS."
  exit 1
fi
