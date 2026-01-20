#!/bin/bash
set -e

log_message() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

log_ok() {
  log_message "OK: $1"
}

log_error() {
  log_message "ERROR: $1"
  exit 1
}

log_warning() {
  log_message "WARNING: $1"
}

log_message "--- Starting Node Health Check ---"
LOCAL_IP=$(hostname -i)

# 1. Disk Space Check
log_message "1. Checking disk space..."
if ! /usr/local/bin/disk-health-check.sh; then
    log_error "Disk space check failed. See output from disk-health-check.sh."
else
    log_ok "Disk space is sufficient."
fi

# 2. Node Status Check
log_message "2. Checking local node status..."
NODE_STATUS=$(nodetool status | grep "$LOCAL_IP" | awk '{print $1}')

if [ "$NODE_STATUS" == "UN" ]; then
    log_ok "Node status is UN (Up/Normal)."
elif [ -z "$NODE_STATUS" ]; then
    log_error "Could not find local node IP ($LOCAL_IP) in nodetool status output."
else
    log_error "Node status is '$NODE_STATUS', not UN."
fi

# 3. Gossip Check
log_message "3. Checking gossip status..."
GOSSIP_STATUS=$(nodetool gossipinfo | grep "STATUS" | grep "$LOCAL_IP" | cut -d':' -f2)
if [[ "$GOSSIP_STATUS" == "NORMAL" ]]; then
    log_ok "Gossip state is NORMAL."
else
    log_warning "Gossip state is '$GOSSIP_STATUS', not NORMAL. This might be temporary."
fi

# 4. Check for active streams
log_message "4. Checking for network streams..."
if ! nodetool netstats | grep -q "Mode: NORMAL"; then
    log_warning "Node is not in NORMAL mode. It might be streaming, joining, or leaving."
    nodetool netstats
else
    log_ok "Network mode is NORMAL."
fi

# 5. Check for exceptions in the log
log_message "5. Scanning system log for recent exceptions..."
if journalctl -u cassandra -S "10 minutes ago" | grep -q "Exception"; then
    log_warning "Found 'Exception' in Cassandra logs from the last 10 minutes. Please review logs manually."
    journalctl -u cassandra -S "10 minutes ago" | grep "Exception" | tail -n 10
else
    log_ok "No recent exceptions found in logs."
fi

log_message "--- Node Health Check Completed ---"
