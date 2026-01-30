#!/bin/bash
# This file is managed by Puppet.
set -euo pipefail

# --- Color Codes ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# --- Configuration ---
DISK_CHECK_PATH="/var/lib/cassandra/data"
WARNING_THRESHOLD=75
CRITICAL_THRESHOLD=85
LOG_FILE="/var/log/cassandra/repair.log"
LOCK_FILE="/run/cassandra/repair.lock"
PAUSE_FILE="/var/lib/repairpaused"

# The new python script will log to stdout, which will be captured by systemd's journal.
# We will still use this log file for the shell wrapper's messages.
log_message() {
    echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# --- Argument Parsing ---
KEYSPACE=""
HOURS=0
# Loop through all arguments to parse flags and positional args
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --hours)
            if [[ "$2" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
                HOURS="$2"
                shift 2
            else
                log_message "${RED}ERROR: --hours requires a numeric value.${NC}"
                exit 1
            fi
            ;;
        -*)
            log_message "${RED}ERROR: Unknown option '$1'.${NC}"
            exit 1
            ;;
        *)
            # Non-flag argument is the keyspace
            if [ -z "$KEYSPACE" ]; then
                KEYSPACE="$1"
            else
                log_message "${RED}ERROR: Unexpected argument '$1'. Only one keyspace can be specified.${NC}"
                exit 1
            fi
            shift
            ;;
    esac
done

# --- Pre-flight Checks ---

# 1. Lock File Management
if [ -f "$LOCK_FILE" ]; then
    OLD_PID=$(cat "$LOCK_FILE")
    if ps -p "$OLD_PID" > /dev/null; then
        log_message "${YELLOW}Repair process with PID $OLD_PID is still running. Skipping this scheduled run.${NC}"
        exit 0
    else
        log_message "${YELLOW}Found stale lock file for dead PID $OLD_PID. Removing and proceeding.${NC}"
        rm -f "$LOCK_FILE"
    fi
fi

# 2. Pause File Check
if [ -f "$PAUSE_FILE" ]; then
    log_message "${YELLOW}Repair is paused due to presence of $PAUSE_FILE. Skipping this run.${NC}"
    exit 0
fi

# Create lock file and set trap to remove it on exit
echo $$ > "$LOCK_FILE"
trap 'rm -f "$LOCK_FILE"' EXIT

log_message "${BLUE}--- Starting Granular Repair Manager ---${NC}"
log_message "${BLUE}Lock file created at $LOCK_FILE with PID $$.${NC}"

# 3. Pre-flight disk space check
log_message "${BLUE}Performing pre-flight disk usage check...${NC}"
if ! /usr/local/bin/disk-health-check.sh -p "$DISK_CHECK_PATH" -w "$WARNING_THRESHOLD" -c "$CRITICAL_THRESHOLD"; then
    log_message "${RED}ERROR: Pre-flight disk usage check failed. Aborting repair to prevent disk space issues.${NC}"
    exit 1 # trap will remove the lock file
fi
log_message "${GREEN}Disk usage OK. Proceeding with repair.${NC}"

# --- Command Execution ---

# Build the command to execute
PYTHON_CMD_ARRAY=("/usr/local/bin/cassandra_range_repair.py")
if [ "$HOURS" != "0" ]; then
    PYTHON_CMD_ARRAY+=("--hours" "$HOURS")
    log_message "${BLUE}Repair timed to complete in $HOURS hours.${NC}"
fi
if [ -n "$KEYSPACE" ]; then
    PYTHON_CMD_ARRAY+=("$KEYSPACE")
    log_message "${BLUE}Targeting keyspace: $KEYSPACE${NC}"
else
    log_message "${BLUE}Targeting all non-system keyspaces.${NC}"
fi

# Execute repair via python script
log_message "${BLUE}Executing command: ${PYTHON_CMD_ARRAY[*]}${NC}"
# The python script's logging goes to stdout, which journald will capture.
if "${PYTHON_CMD_ARRAY[@]}"; then
    log_message "${GREEN}--- Granular Repair Finished Successfully ---${NC}"
    # trap will remove the lock file
    exit 0
else
    REPAIR_EXIT_CODE=$?
    log_message "${RED}ERROR: Granular repair script failed with exit code $REPAIR_EXIT_CODE. See journalctl -u cassandra-repair.service for details.${NC}"
    # trap will remove the lock file
    exit $REPAIR_EXIT_CODE
fi
