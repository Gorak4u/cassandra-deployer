#!/bin/bash
# A script to perform pre-flight checks before a major Cassandra upgrade (e.g., 3.x to 4.x).
set -euo pipefail

# --- Color Codes ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# --- Logging ---
log_message() {
    echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

log_info() { log_message "${BLUE}$1${NC}"; }
log_success() { log_message "${GREEN}$1${NC}"; }
log_warn() { log_message "${YELLOW}$1${NC}"; }
log_error() { log_message "${RED}$1${NC}"; }

FINAL_STATUS=0 # 0 for success, 1 for failure

check_step() {
    local description="$1"
    shift
    local command_to_run="$@"

    log_info "CHECK: $description"
    if ! eval "$command_to_run"; then
        log_error "RESULT: FAILED"
        FINAL_STATUS=1
    else
        log_success "RESULT: PASSED"
    fi
    echo ""
}

log_info "--- Cassandra Pre-Upgrade Check ---"
log_warn "This script performs checks for upgrading from Cassandra 3.x to 4.x."
log_warn "Ensure this script is run on every node in the cluster before proceeding with the upgrade."
echo ""

# 1. Check if nodetool drain has been run
check_step "Node has been drained" \
    "nodetool netstats | grep -q 'Mode: DRAINED'"

# 2. Check for schema agreement
check_step "All nodes agree on the schema version" \
    "[[ $(nodetool describecluster | grep 'Schema versions:' | awk -F': ' '{print $2}' | tr -d '[]' | tr ',' '\n' | sort -u | wc -l) -eq 1 ]]"

# 3. Check for sstables that need upgrading
check_step "All SSTables are on the current version" \
    "! nodetool upgradesstables -a --list-only | grep -q ."

# 4. Check for running compactions
check_step "No compactions are currently in progress" \
    "[[ $(nodetool compactionstats | grep 'pending tasks' | awk '{print $3}') -eq 0 ]]"

# 5. Check for active streams
check_step "No active network streams" \
    "nodetool netstats | grep 'Mode: NORMAL'"

# 6. Check system_auth replication factor
check_step "system_auth keyspace is replicated across all datacenters" \
    "cqlsh -e \"DESCRIBE KEYSPACE system_auth\" | grep 'NetworkTopologyStrategy'"

log_info "--- Pre-Upgrade Check Summary ---"
if [ $FINAL_STATUS -eq 0 ]; then
    log_success "All pre-upgrade checks passed. This node appears ready for upgrade."
    log_warn "Remember to take a full backup before starting the upgrade process."
else
    log_error "One or more pre-upgrade checks failed. Please review the output above and resolve the issues before attempting to upgrade."
fi

exit $FINAL_STATUS
