#!/bin/bash
# Checks Cassandra cluster health, Cqlsh connectivity, and native transport port

IP_ADDRESS=""
if [ -n "$1" ]; then
    IP_ADDRESS="$1"
else
    IP_ADDRESS="$(hostname -I | awk '{print $1}')"
fi
CQLSH_CONFIG="/root/.cassandra/cqlshrc"

log_message() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# 1. Check nodetool status for 'UN' (Up, Normal)
log_message "Checking nodetool status..."
NODETOOL_STATUS=$(nodetool status 2>&1)
if echo "$NODETOOL_STATUS" | grep -q 'UN'; then
  log_message "Nodetool status: OK - At least one Up/Normal node found."
else
  log_message "Nodetool status: WARNING - No Up/Normal nodes found or nodetool failed."
  echo "$NODETOOL_STATUS"
  # return 1 # Don't exit here, might be starting up
fi

# 2. Check cqlsh connectivity
log_message "Checking cqlsh connectivity using $CQLSH_CONFIG..."
if cqlsh --cqlshrc "$CQLSH_CONFIG" "$IP_ADDRESS" -e "SELECT cluster_name FROM system.local;" >/dev/null 2>&1; then
  log_message "Cqlsh connectivity: OK"
else
  log_message "Cqlsh connectivity: FAILED"
  return 1
fi

# 3. Check native transport port 9042 using nc
log_message "Checking native transport port 9042..."
if nc -z -w 5 "$IP_ADDRESS" 9042 >/dev/null 2>&1; then
  log_message "Port 9042 (Native Transport): OPEN"
else
  log_message "Port 9042 (Native Transport): CLOSED or FAILED"
  return 1
fi

log_message "Cluster health check completed successfully."
exit 0
