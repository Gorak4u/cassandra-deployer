#!/bin/bash
set -euo pipefail

LOG_FILE="/var/log/cassandra/rolling_restart.log"

log_message() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
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
    if nodetool status | grep "$(hostname -i)" | grep -q 'UN'; then
        CASSANDRA_READY=true
        break
    fi
    log_message "Waiting for node to report UP/NORMAL... (attempt $i of 30)"
    sleep 10
done

if [ "$CASSANDRA_READY" = true ]; then
    log_message "SUCCESS: Node has rejoined the cluster successfully."
    log_message "--- Rolling Restart Finished ---"
    exit 0
else
    log_message "ERROR: Node failed to return to UN state within 5 minutes. Please investigate."
    exit 1
fi
