#!/bin/bash
# This file is managed by Puppet.
set -euo pipefail

# --- Defaults & Configuration ---
KEYSPACE=""
TABLE_LIST=""
JOBS=0 # 0 means let Cassandra decide
DISK_CHECK_PATH="/var/lib/cassandra/data"
WARNING_THRESHOLD=75
CRITICAL_THRESHOLD=85
LOG_FILE="/var/log/cassandra/manual_repair.log"

# --- Color Codes ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# --- Logging ---
log_message() {
    echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# --- Usage ---
usage() {
    log_message "${YELLOW}Usage: $0 [OPTIONS] [keyspace] [tables...]${NC}"
    log_message "Runs a full 'nodetool repair' on a given keyspace or table with pre-flight checks."
    log_message "  [keyspace]          (Optional) The keyspace to repair. If omitted, all non-system keyspaces are repaired."
    log_message "  [tables...]         (Optional) A space-separated list of tables to repair within the specified keyspace."
    log_message ""
    log_message "Options:"
    log_message "  -j, --jobs <num>    Number of concurrent repair jobs. Default: 0 (auto)"
    log_message "  -h, --help          Show this help message."
    exit 1
}

# --- Argument Parsing ---
# Simplified parsing for positional and one optional flag
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -j|--jobs)
            JOBS="$2"; shift 2 ;;
        -h|--help)
            usage ;;
        -*)
            log_message "${RED}Unknown option: $1${NC}"; usage ;;
        *)
            # Positional arguments
            if [ -z "$KEYSPACE" ]; then
                KEYSPACE="$1"
            else
                TABLE_LIST+="$1 "
            fi
            shift ;;
    esac
done

# --- Main Logic ---
log_message "${BLUE}--- Starting Manual Full Repair ---${NC}"

# Build the nodetool command
CMD="nodetool repair"
TARGET_DESC="all non-system keyspaces"

# Add options
if [[ $JOBS -gt 0 ]]; then
    CMD+=" -j $JOBS"
fi

# Add keyspace/table arguments
if [[ -n "$KEYSPACE" ]]; then
    TARGET_DESC="keyspace '$KEYSPACE'"
    CMD+=" -- $KEYSPACE"
    if [[ -n "$TABLE_LIST" ]]; then
        CMD+=" $TABLE_LIST"
        TARGET_DESC="table(s) '$TABLE_LIST' in keyspace '$KEYSPACE'"
    fi
fi

log_message "${BLUE}Target: $TARGET_DESC${NC}"
log_message "${BLUE}Disk path to check: $DISK_CHECK_PATH${NC}"
log_message "Command to be executed: $CMD"

# Pre-flight disk space check
log_message "${BLUE}Performing pre-flight disk space check...${NC}"
if ! /usr/local/bin/disk-health-check.sh -p "$DISK_CHECK_PATH" -w "$WARNING_THRESHOLD" -c "$CRITICAL_THRESHOLD"; then
    log_message "${RED}ERROR: Pre-flight disk usage check failed. Aborting repair.${NC}"
    exit 1
fi
log_message "${GREEN}Disk usage OK. Proceeding with repair.${NC}"

# Execute the command
if $CMD; then
    log_message "${GREEN}--- Manual Repair Finished Successfully ---${NC}"
    exit 0
else
    REPAIR_EXIT_CODE=$?
    log_message "${RED}ERROR: Nodetool repair command failed with exit code $REPAIR_EXIT_CODE.${NC}"
    exit $REPAIR_EXIT_CODE
fi
