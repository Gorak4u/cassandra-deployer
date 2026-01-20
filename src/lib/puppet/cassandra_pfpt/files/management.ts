
export const managementScripts = {
      'drain-node.sh': `#!/bin/bash
# Drains a node.

log_message() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] \\$1"
}

log_message "Starting nodetool drain..."
nodetool drain
DRAIN_STATUS=\\$?

if [ \\$DRAIN_STATUS -eq 0 ]; then
  log_message "Nodetool drain completed successfully."
  # Wait a bit and check status (optional)
  sleep 5
  NODETOOL_STATUS=\\$(nodetool status)
  if echo "\\$NODETOOL_STATUS" | grep -q "\\\$(hostname -I | awk '{print \\$1}')" | grep -q 'DN'; then
    log_message "Node is in Drained (DN) state."
  else
    log_message "Node is not in Drained (DN) state after drain command."
  fi
  exit 0
else
  log_message "Nodetool drain FAILED with exit code \\$DRAIN_STATUS."
  exit 1
fi
`,
      'decommission-node.sh': `#!/bin/bash
# Securely decommissions a Cassandra node from the cluster.

log_message() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] \\$1"
}

log_message "INFO: This script will decommission the local Cassandra node."
log_message "This process will stream all of its data to other nodes in the cluster."
log_message "It cannot be undone."
log_message "Are you sure you want to proceed? Type 'yes' to confirm."

read -r confirmation

if [ "\\$confirmation" != "yes" ]; then
  log_message "Aborted. Node was not decommissioned."
  exit 0
fi

log_message "Starting nodetool decommission..."
nodetool decommission

DECOMMISSION_STATUS=\\$?

if [ \\$DECOMMISSION_STATUS -eq 0 ]; then
  log_message "SUCCESS: Nodetool decommission completed successfully."
  log_message "It is now safe to shut down the cassandra service and turn off this machine."
  exit 0
else
  log_message "ERROR: Nodetool decommission FAILED with exit code \\$DECOMMISSION_STATUS."
  log_message "Check the system logs for more information. Do NOT shut down this node until the issue is resolved."
  exit 1
fi
`,
      'assassinate-node.sh': `#!/bin/bash
# Assassinate a node. Use with extreme caution.

log_message() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] \\$1"
}

NODE_IP="\\$1"

if [ -z "\\$NODE_IP" ]; then
  log_message "Error: Node IP address must be provided as an argument."
  log_message "Usage: \\$0 <ip_address_of_dead_node>"
  exit 1
fi

log_message "WARNING: Attempting to assassinate node at IP: \\$NODE_IP. This will remove it from the cluster."
log_message "Are you sure you want to proceed? Type 'yes' to confirm."
read confirmation

if [ "\\$confirmation" != "yes" ]; then
  log_message "Aborted."
  exit 0
fi

nodetool assassinate "\\$NODE_IP"
ASSASSINATE_STATUS=\\$?

if [ \\$ASSASSINATE_STATUS -eq 0 ]; then
  log_message "Nodetool assassinate of \\$NODE_IP completed successfully."
  exit 0
else
  log_message "Nodetool assassinate of \\$NODE_IP FAILED with exit code \\$ASSASSINATE_STATUS."
  exit 1
fi
`,
      'rebuild-node.sh': `#!/bin/bash
set -euo pipefail

SOURCE_DC="\\$1"

log_message() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] \\$1"
}

if [ -z "\\$SOURCE_DC" ]; then
    log_message "ERROR: Source datacenter must be provided as the first argument."
    log_message "Usage: \\$0 <source_datacenter_name>"
    exit 1
fi

log_message "--- Starting Node Rebuild from DC: \\$SOURCE_DC ---"
log_message "This will stream data from other replicas to this node."
log_message "Ensure this node is stopped, its data directory is empty, and it has started up again before running this."
read -p "Are you sure you want to continue? Type 'yes': " confirmation
if [[ "\\$confirmation" != "yes" ]]; then
    log_message "Rebuild aborted by user."
    exit 0
fi

log_message "Starting nodetool rebuild..."
if nodetool rebuild -- "\\$SOURCE_DC"; then
    log_message "SUCCESS: Nodetool rebuild completed successfully."
    exit 0
else
    REBUILD_STATUS=\\$?
    log_message "ERROR: Nodetool rebuild FAILED with exit code \\$REBUILD_STATUS."
    exit \\$REBUILD_STATUS
fi
`,
      'prepare-replacement.sh': `#!/bin/bash
set -euo pipefail

DEAD_NODE_IP="\\$1"
JVM_OPTIONS_FILE="/etc/cassandra/conf/jvm-server.options"

log_message() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] \\$1"
}

if [ -z "\\$DEAD_NODE_IP" ]; then
    log_message "ERROR: IP address of the dead node to replace must be provided."
    log_message "Usage: \\$0 <ip_of_dead_node>"
    exit 1
fi

if [ ! -f "\\$JVM_OPTIONS_FILE" ]; then
    log_message "ERROR: JVM options file not found at \\$JVM_OPTIONS_FILE"
    exit 1
fi

log_message "--- Preparing Node for Replacement ---"
log_message "This script will configure this node to replace the dead node at IP: \\$DEAD_NODE_IP."
read -p "Are you sure? This should be run on a NEW, STOPPED node. Type 'yes': " confirmation
if [[ "\\$confirmation" != "yes" ]]; then
    log_message "Aborted by user."
    exit 0
fi

# Clean up any previous replacement flags
log_message "Removing any existing replace_address flags from \\$JVM_OPTIONS_FILE..."
sed -i '/-Dcassandra.replace_address/d' "\\$JVM_OPTIONS_FILE"

# Add the new flag
log_message "Adding replacement flag: -Dcassandra.replace_address_first_boot=\\$DEAD_NODE_IP"
echo "-Dcassandra.replace_address_first_boot=\\$DEAD_NODE_IP" >> "\\$JVM_OPTIONS_FILE"

log_message "SUCCESS: Node is configured for replacement."
log_message "You can now start the Cassandra service. It will bootstrap and replace the dead node."
exit 0
`,
      'rolling_restart.sh': `#!/bin/bash
set -euo pipefail

LOG_FILE="/var/log/cassandra/rolling_restart.log"

log_message() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] \\$1" | tee -a "\\$LOG_FILE"
}

log_message "--- Starting Safe Rolling Restart of Cassandra Node ---"

# 1. Drain the node
log_message "Step 1: Draining node (flushing memtables and stopping listeners)..."
if ! nodetool drain; then
    log_message "ERROR: Failed to drain the node. Aborting restart."
    exit 1
fi
log_message "Node drained successfully."

# 2. Stop the service
log_message "Step 2: Stopping the cassandra service..."
if ! systemctl stop cassandra; then
    log_message "ERROR: Failed to stop the cassandra service. Please check 'systemctl status cassandra'."
    exit 1
fi
log_message "Service stopped."

# 3. Start the service
log_message "Step 3: Starting the cassandra service..."
if ! systemctl start cassandra; then
    log_message "ERROR: Failed to start the cassandra service. Please check 'systemctl status cassandra' and logs."
    exit 1
fi
log_message "Service start command issued. Waiting for node to initialize..."

# 4. Wait for node to be UP and NORMAL
CASSANDRA_READY=false
for i in {1..30}; do # Wait up to 5 minutes (30 * 10 seconds)
    # Grep for this node's IP in status output, check for 'UN'
    if nodetool status | grep "\\\$(hostname -i)" | grep -q 'UN'; then
        CASSANDRA_READY=true
        break
    fi
    log_message "Waiting for node to report UP/NORMAL... (attempt \\$i of 30)"
    sleep 10
done

if [ "\\$CASSANDRA_READY" = true ]; then
    log_message "SUCCESS: Node has rejoined the cluster successfully."
    log_message "--- Rolling Restart Finished ---"
    exit 0
else
    log_message "ERROR: Node failed to return to UN state within 5 minutes. Please investigate."
    exit 1
fi
`,
};

    
