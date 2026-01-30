#!/bin/bash
# This file is managed by Puppet.
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
JSON_MODE=false
# Array to hold JSON for each check
CHECKS_JSON_ARRAY=()

# --- Helper Functions ---
log_message() {
  if [ "$JSON_MODE" = false ]; then
    echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
  fi
}

add_check_result() {
    local check_name="$1"
    local status="$2"
    local message="$3"
    local details="${4:-}"
    
    local check_json
    check_json=$(jq -n \
        --arg name "$check_name" \
        --arg status "$status" \
        --arg msg "$message" \
        '{name: $name, status: $status, message: $msg}')
    
    if [ -n "$details" ]; then
        check_json=$(echo "$check_json" | jq --arg details "$details" '. + {details: $details}')
    fi
    CHECKS_JSON_ARRAY+=("$check_json")
}

log_ok() {
  if [ "$JSON_MODE" = true ]; then
    add_check_result "$CURRENT_CHECK_NAME" "OK" "$1"
  else
    log_message "${GREEN}OK: $1${NC}"
  fi
}

log_error() {
  ((FAILURES++))
  if [ "$JSON_MODE" = true ]; then
    add_check_result "$CURRENT_CHECK_NAME" "ERROR" "$1" "$2"
  else
    log_message "${RED}ERROR: $1${NC}"
  fi
}

log_warning() {
  ((WARNINGS++))
  if [ "$JSON_MODE" = true ]; then
    add_check_result "$CURRENT_CHECK_NAME" "WARNING" "$1" "$2"
  else
    log_message "${YELLOW}WARNING: $1${NC}"
  fi
}

header() {
    if [ "$JSON_MODE" = false ]; then
      echo -e "\n${BLUE}--- $1 ---${NC}"
    fi
}

# --- Argument Parsing ---
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --json) JSON_MODE=true; shift ;;
        *) log_message "Unknown parameter passed: $1"; exit 1 ;;
    esac
done

# --- Check Functions ---

check_disk_space() {
    header "1. Checking Disk Space"
    CURRENT_CHECK_NAME="disk_space"
    local disk_check_output
    disk_check_output=$(/usr/local/bin/disk-health-check.sh 2>&1)
    local disk_check_status=$?

    if [ $disk_check_status -eq 0 ]; then
        log_ok "$disk_check_output"
    elif [ $disk_check_status -eq 1 ]; then
        log_warning "$disk_check_output"
    elif [ $disk_check_status -eq 2 ]; then
        log_error "$disk_check_output"
    else
        log_error "Disk health check script failed with unexpected exit code: $disk_check_status" "$disk_check_output"
    fi
}

check_node_status() {
    header "2. Checking Node Status"
    CURRENT_CHECK_NAME="node_status"
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
    CURRENT_CHECK_NAME="schema_agreement"
    local schema_versions_output
    schema_versions_output=$(nodetool describecluster 2>/dev/null)
    local schema_versions
    schema_versions=$(echo "$schema_versions_output" | grep 'Schema versions:' | awk '{print $NF}' | tr -d '[]' | tr ',' ' ' | wc -w)
    
    if [[ "$schema_versions" == "1" ]]; then
        log_ok "Schema is in agreement across the cluster."
    elif [[ "$schema_versions" -gt 1 ]]; then
        log_error "Schema disagreement detected! Found $schema_versions different schema versions." "$schema_versions_output"
    else
        log_warning "Could not determine schema agreement from 'nodetool describecluster'." "$schema_versions_output"
    fi
}

check_gossip() {
    header "4. Checking Gossip Status"
    CURRENT_CHECK_NAME="gossip_status"
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
    CURRENT_CHECK_NAME="network_streams"
    local netstats_output
    netstats_output=$(nodetool netstats 2>/dev/null)
    if echo "$netstats_output" | grep -q "Mode: NORMAL"; then
        log_ok "Network mode is NORMAL."
    else
        log_warning "Node is not in NORMAL mode. It might be streaming, joining, or leaving." "$netstats_output"
    fi
}

check_pending_compactions() {
    header "6. Checking for Pending Compactions"
    CURRENT_CHECK_NAME="pending_compactions"
    local pending_tasks
    pending_tasks=$(nodetool compactionstats 2>/dev/null | grep "pending tasks" | awk '{print $3}')
    if [[ "$pending_tasks" =~ ^[0-9]+$ ]] && [[ "$pending_tasks" -gt 50 ]]; then
        log_warning "High number of pending compaction tasks: $pending_tasks."
    elif [[ "$pending_tasks" =~ ^[0-9]+$ ]]; then
        log_ok "Pending compaction tasks are within a reasonable range ($pending_tasks)."
    else
        log_warning "Could not parse pending compaction tasks."
    fi
}

check_dropped_messages() {
    header "7. Checking for Dropped Messages"
    CURRENT_CHECK_NAME="dropped_messages"
    local dropped_count
    local tpstats_output
    tpstats_output=$(nodetool tpstats 2>/dev/null)
    # Sum up the 'Dropped' column from all pools
    dropped_count=$(echo "$tpstats_output" | awk 'NR > 2 { sum += $5 } END { print sum }')
    if [[ "$dropped_count" =~ ^[0-9]+$ ]] && [[ "$dropped_count" -gt 0 ]]; then
        log_warning "Found $dropped_count dropped messages across all thread pools. This may indicate an overloaded node." "$(echo "$tpstats_output" | grep -v ' 0 /')"
    elif [[ "$dropped_count" =~ ^[0-9]+$ ]]; then
        log_ok "No dropped messages detected."
    else
        log_warning "Could not parse dropped message count from tpstats."
    fi
}

check_log_exceptions() {
    header "8. Scanning System Log for Recent Exceptions"
    CURRENT_CHECK_NAME="log_exceptions"
    local recent_exceptions
    recent_exceptions=$(journalctl -u cassandra -S "10 minutes ago" | grep "Exception" || true)

    if [ -n "$recent_exceptions" ]; then
        log_warning "Found 'Exception' in Cassandra logs from the last 10 minutes. Please review logs manually." "$(echo "$recent_exceptions" | tail -n 10)"
    else
        log_ok "No recent exceptions found in logs."
    fi
}

# --- Main Execution ---
if [ "$JSON_MODE" = false ]; then
  log_message "${BLUE}========= Starting Node Health Check =========${NC}"
fi

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
if [ "$JSON_MODE" = true ]; then
    final_status="OK"
    if [ "$FAILURES" -gt 0 ]; then
        final_status="ERROR"
    elif [ "$WARNINGS" -gt 0 ]; then
        final_status="WARNING"
    fi
    
    # Build the final JSON object
    all_checks_json=$(printf ",%s" "${CHECKS_JSON_ARRAY[@]}")
    all_checks_json=${all_checks_json:1} # Remove leading comma

    jq -n \
        --arg status "$final_status" \
        --argjson failures "$FAILURES" \
        --argjson warnings "$WARNINGS" \
        --argjson checks "[$all_checks_json]" \
        '{overall_status: $status, failures: $failures, warnings: $warnings, checks: $checks}'

else
    header "Health Check Summary"
    if [ "$FAILURES" -gt 0 ]; then
        log_message "${RED}Result: FAILED. Found $FAILURES critical error(s) and $WARNINGS warning(s).${NC}"
        log_message "${RED}Do NOT proceed with maintenance until errors are resolved.${NC}"
    elif [ "$WARNINGS" -gt 0 ]; then
        log_message "${YELLOW}Result: PASSED with $WARNINGS warning(s). Proceed with caution.${NC}"
    else
        log_message "${GREEN}Result: PASSED. Node appears healthy.${NC}"
    fi
fi

# Set exit code based on severity for scripting
if [ "$FAILURES" -gt 0 ]; then
    exit 1
elif [ "$WARNINGS" -gt 0 ]; then
    exit 2 # Different exit code for warnings
else
    exit 0
fi
