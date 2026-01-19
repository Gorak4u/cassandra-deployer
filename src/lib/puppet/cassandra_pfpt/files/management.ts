
export const managementScripts = {
      'drain-node.sh': '#!/bin/bash\\nnodetool drain',
      'decommission-node.sh': `#!/bin/bash
# Securely decommissions a Cassandra node from the cluster.

log_message() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

log_message "INFO: This script will decommission the local Cassandra node."
log_message "This process will stream all of its data to other nodes in the cluster."
log_message "It cannot be undone."
log_message "Are you sure you want to proceed? Type 'yes' to confirm."

read -r confirmation

if [ "$confirmation" != "yes" ]; then
  log_message "Aborted. Node was not decommissioned."
  exit 0
fi

log_message "Starting nodetool decommission..."
nodetool decommission

DECOMMISSION_STATUS=$?

if [ $DECOMMISSION_STATUS -eq 0 ]; then
  log_message "SUCCESS: Nodetool decommission completed successfully."
  log_message "It is now safe to shut down the cassandra service and turn off this machine."
  exit 0
else
  log_message "ERROR: Nodetool decommission FAILED with exit code $DECOMMISSION_STATUS."
  log_message "Check the system logs for more information. Do NOT shut down this node until the issue is resolved."
  exit 1
fi
`,
      'assassinate-node.sh': `#!/bin/bash
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
`,
      'rebuild-node.sh': '#!/bin/bash\\necho "Rebuild Node Script"',
      'prepare-replacement.sh': '#!/bin/bash\\necho "Prepare Replacement Script"',
      'rolling_restart.sh': '#!/bin/bash\\necho "Rolling Restart Script Placeholder"',
};
