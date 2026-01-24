#!/bin/bash
# This file is managed by Puppet.
set -euo pipefail

# --- Defaults & Configuration ---
KEYSPACE=""
TABLE_LIST=""
JOBS=0 # 0 means let Cassandra decide
DISK_CHECK_PATH="/var/lib/cassandra/data"
WARNING_THRESHOLD=70 # Upgrade can be disk intensive
CRITICAL_THRESHOLD=80
LOG_FILE="/var/log/cassandra/upgradesstables.log"

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
    log_message "${YELLOW}Usage: $0 [OPTIONS]${NC}"
    log_message "Safely runs 'nodetool upgradesstables' with pre-flight disk space checks."
    log_message "This is typically run after a major version upgrade of Cassandra."
    log_message "  -k, --keyspace <name>       Specify the keyspace. Required if specifying tables."
    log_message "  -t, --table <name>          Specify a table to upgrade. Can be used multiple times."
    log_message "  -j, --jobs <num>            Number of concurrent sstable upgrade jobs. Default: 0 (auto)"
    log_message "  -d, --disk-path <path>      Path to monitor for disk space. Default: $DISK_CHECK_PATH"
    log_message "  -w, --warning <%>           Warning disk usage threshold (%). Aborts if above. Default: $WARNING_THRESHOLD"
    log_message "  -c, --critical <%>          Critical disk usage threshold (%). Aborts if above. Default: $CRITICAL_THRESHOLD"
    log_message "  -h, --help                  Show this help message."
    exit 1
}

# --- Argument Parsing ---
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -k|--keyspace) KEYSPACE="$2"; shift ;;
        -t|--table) TABLE_LIST="$TABLE_LIST $2"; shift ;;
        -j|--jobs) JOBS="$2"; shift ;;
        -d|--disk-path) DISK_CHECK_PATH="$2"; shift ;;
        -w|--warning) WARNING_THRESHOLD="$2"; shift ;;
        -c|--critical) CRITICAL_THRESHOLD="$2"; shift ;;
        -h|--help) usage ;;
        *) log_message "${RED}Unknown parameter passed: $1${NC}"; usage ;;
    esac
    shift
done

if [[ -n "$TABLE_LIST" && -z "$KEYSPACE" ]]; then
    log_message "${RED}ERROR: A keyspace (-k) must be specified when upgrading specific tables (-t).${NC}"
    exit 1
fi

# --- Main Logic ---
log_message "${BLUE}--- Starting SSTable Upgrade Manager ---${NC}"

# Build the nodetool command
CMD="nodetool upgradesstables"
TARGET_DESC="all keyspaces and tables"

# Add options
if [[ $JOBS -gt 0 ]]; then
    CMD+=" -j $JOBS"
fi

# Add keyspace/table arguments
if [[ -n "$KEYSPACE" ]]; then
    TARGET_DESC="keyspace '$KEYSPACE'"
    CMD+=" -- $KEYSPACE"
    if [[ -n "$TABLE_LIST" ]]; then
        CMD+=$TABLE_LIST
        CLEAN_TABLE_LIST=$(echo "$TABLE_LIST" | sed 's/^ *//g')
        TARGET_DESC="table(s) '$CLEAN_TABLE_LIST' in keyspace '$KEYSPACE'"
    fi
else
    # If no keyspace is provided, nodetool upgrades all sstables. The -a flag is implied.
    CMD+=" -a"
fi

log_message "${BLUE}Target: $TARGET_DESC${NC}"
log_message "${BLUE}Disk path to check: $DISK_CHECK_PATH${NC}"
log_message "${BLUE}Warning usage threshold: $WARNING_THRESHOLD%${NC}"
log_message "${BLUE}Critical usage threshold: $CRITICAL_THRESHOLD%${NC}"
log_message "Command to be executed: $CMD"

# Pre-flight disk space check
log_message "${BLUE}Performing pre-flight disk usage check...${NC}"
if ! /usr/local/bin/disk-health-check.sh -p "$DISK_CHECK_PATH" -w "$WARNING_THRESHOLD" -c "$CRITICAL_THRESHOLD"; then
    log_message "${RED}ERROR: Pre-flight disk usage check failed. Aborting SSTable upgrade to prevent disk space issues.${NC}"
    exit 1
fi
log_message "${GREEN}Disk usage OK. Proceeding with SSTable upgrade.${NC}"

# Execute the command
if $CMD; then
    log_message "${GREEN}--- SSTable Upgrade Finished Successfully ---${NC}"
    exit 0
else
    UPGRADE_EXIT_CODE=$?
    log_message "${RED}ERROR: SSTable upgrade command failed with exit code $UPGRADE_EXIT_CODE.${NC}"
    exit $UPGRADE_EXIT_CODE
fi
