#!/bin/bash
# A comprehensive, non-invasive health check for a Cassandra node.

# --- Color Codes ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# --- State Counters ---
FAILURES=0
WARNINGS=0

# --- Helper Functions ---
log_message() {
  echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

log_ok() {
  log_message "${GREEN}OK: $1${NC}"
}

log_error() {
  log_message "${RED}ERROR: $1${NC}"
  ((FAILURES++))
}

log_warning() {
  log_message "${YELLOW}WARNING: $1${NC}"
  ((WARNINGS++))
}

header() {
    echo -e "\n${BLUE}--- $1 ---${NC}"
}

# --- Check Functions ---

check_disk_space() {
    header "1. Checking Disk Space"
    if ! /usr/local/bin/disk-health-check.sh; then
        # The disk health check script already logs the specific error
        log_error "Disk space check failed."
    else
        log_ok "Disk space is sufficient."
    fi
}

check_node_status() {
    header "2. Checking Node Status"
    local local_ip
    local_ip=$(hostname -i)
    local node_status
    node_status=$(nodetool status 2>/dev/null | grep "$local_ip" | awk '{print $1}')

    if [ "$node_status" == "UN" ]; then
        log_ok "Node status is UN (Up/Normal)."
    elif [ -z "$node_status" ]; then
        log_error "Could not find local node IP ($local_ip) in nodetool status output."
    else
        log_error "Node status is '$node_status', not UN."
    fi
}

check_schema_agreement() {
    header "3. Checking Schema Agreement"
    local schema_versions
    schema_versions=$(nodetool describecluster 2>/dev/null | grep 'Schema versions:' | awk '{print $NF}' | tr -d '[]' | tr ',' ' ' | wc -w)
    
    if [[ "$schema_versions" == "1" ]]; then
        log_ok "Schema is in agreement across the cluster."
    elif [[ "$schema_versions" -gt 1 ]]; then
        log_error "Schema disagreement detected! Found $schema_versions different schema versions."
        nodetool describecluster
    else
        log_warning "Could not determine schema agreement from 'nodetool describecluster'."
    fi
}

check_gossip() {
    header "4. Checking Gossip Status"
    local local_ip
    local_ip=$(hostname -i)
    local gossip_status
    gossip_status=$(nodetool gossipinfo 2>/dev/null | grep "STATUS" | grep "$local_ip" | cut -d':' -f2 | xargs)
    if [[ "$gossip_status" == "NORMAL" ]]; then
        log_ok "Gossip state is NORMAL."
    elif [ -n "$gossip_status" ]; then
        log_warning "Gossip state is '$gossip_status', not NORMAL. This might be temporary."
    else
        log_warning "Could not determine gossip status for local node."
    fi
}

check_network_streams() {
    header "5. Checking for Network Streams"
    if ! nodetool netstats 2>/dev/null | grep -q "Mode: NORMAL"; then
        log_warning "Node is not in NORMAL mode. It might be streaming, joining, or leaving."
        nodetool netstats
    else
        log_ok "Network mode is NORMAL."
    fi
}

check_pending_compactions() {
    header "6. Checking for Pending Compactions"
    local pending_tasks
    pending_tasks=$(nodetool compactionstats 2>/dev/null | grep "pending tasks" | awk '{print $3}')
    if [[ "$pending_tasks" -gt 50 ]]; then
        log_warning "High number of pending compaction tasks: $pending_tasks."
    else
        log_ok "Pending compaction tasks are within a reasonable range ($pending_tasks)."
    fi
}

check_dropped_messages() {
    header "7. Checking for Dropped Messages"
    local dropped_count
    # Sum up the 'Dropped' column from all pools
    dropped_count=$(nodetool tpstats 2>/dev/null | awk 'NR > 2 { sum += $5 } END { print sum }')
    if [[ "$dropped_count" -gt 0 ]]; then
        log_warning "Found $dropped_count dropped messages across all thread pools. This may indicate an overloaded node."
        nodetool tpstats | grep -v ' 0 /'
    else
        log_ok "No dropped messages detected."
    fi
}

check_log_exceptions() {
    header "8. Scanning System Log for Recent Exceptions"
    if journalctl -u cassandra -S "10 minutes ago" | grep -q "Exception"; then
        log_warning "Found 'Exception' in Cassandra logs from the last 10 minutes. Please review logs manually."
        journalctl -u cassandra -S "10 minutes ago" | grep "Exception" | tail -n 10
    else
        log_ok "No recent exceptions found in logs."
    fi
}

# --- Main Execution ---
log_message "${BLUE}========= Starting Node Health Check =========${NC}"

# Run all checks
check_disk_space
check_node_status
check_schema_agreement
check_gossip
check_network_streams
check_pending_compactions
check_dropped_messages
check_log_exceptions

# --- Final Summary ---
header "Health Check Summary"
if [ "$FAILURES" -gt 0 ]; then
    log_message "${RED}Result: FAILED. Found $FAILURES critical error(s) and $WARNINGS warning(s).${NC}"
    log_message "${RED}Do NOT proceed with maintenance until errors are resolved.${NC}"
    exit 1
elif [ "$WARNINGS" -gt 0 ]; then
    log_message "${YELLOW}Result: PASSED with $WARNINGS warning(s). Proceed with caution.${NC}"
    exit 0
else
    log_message "${GREEN}Result: PASSED. Node appears healthy.${NC}"
    exit 0
fi
