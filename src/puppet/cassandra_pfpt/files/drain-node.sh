#!/bin/bash
# Drains a node.

log_message() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

log_message "Starting nodetool drain..."
nodetool drain
DRAIN_STATUS=$?

if [ $DRAIN_STATUS -eq 0 ]; then
  log_message "Nodetool drain completed successfully."
  # Wait a bit and check status (optional)
  sleep 5
  NODETOOL_STATUS=$(nodetool status)
  if echo "$NODETOOL_STATUS" | grep -q "$(hostname -I | awk '{print $1}')" | grep -q 'DN'; then
    log_message "Node is in Drained (DN) state."
  else
    log_message "Node is not in Drained (DN) state after drain command."
  fi
  exit 0
else
  log_message "Nodetool drain FAILED with exit code $DRAIN_STATUS."
  exit 1
fi
