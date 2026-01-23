#!/bin/bash
set -euo pipefail

# --- Defaults & Configuration ---
KEYSPACE=""
TABLE_LIST=""
GRANULARITY="ROW"
JOBS=0 # 0 means let Cassandra decide
DISK_CHECK_PATH="/var/lib/cassandra/data"
WARNING_THRESHOLD=70
CRITICAL_THRESHOLD=80
LOG_FILE="/var/log/cassandra/garbagecollect.log"

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
    log_message "Safely runs 'nodetool garbagecollect' with pre-flight disk space checks."
    log_message "  -k, --keyspace <name>       Specify the keyspace. Required if specifying tables."
    log_message "  -t, --table <name>          Specify a table to collect. Can be used multiple times."
    log_message "  -g, --granularity <CELL|ROW> Granularity of tombstones to remove. Default: ROW"
    log_message "  -j, --jobs <num>            Number of concurrent sstable garbage collection jobs. Default: 0 (auto)"
    log_message "  -d, --disk-path <path>      Path to monitor for disk space. Default: $DISK_CHECK_PATH"
    log_message "  -w, --warning <%>           Warning disk usage threshold (%). Aborts if above. Default: $WARNING_THRESHOLD"
    log_message "  -c, --critical <%>          Critical disk usage threshold (%). Aborts if above. Default: $CRITICAL_THRESHOLD"
    log_message "  -h, --help                  Show this help message."
    log_message ""
    log_message "Examples:"
    log_message "  Collect on entire node:       $0"
    log_message "  Collect on a keyspace:        $0 -k my_keyspace"
    log_message "  Collect on specific tables:   $0 -k my_keyspace -t users -t audit_log"
    log_message "  Collect with cell granularity: $0 -k my_keyspace -t users -g CELL"
    exit 1
}

# --- Argument Parsing ---
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -k|--keyspace) KEYSPACE="$2"; shift ;;
        -t|--table) TABLE_LIST="$TABLE_LIST $2"; shift ;;
        -g|--granularity) GRANULARITY="$2"; shift ;;
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
    log_message "${RED}ERROR: A keyspace (-k) must be specified when collecting on specific tables (-t).${NC}"
    exit 1
fi

# --- Main Logic ---
log_message "${BLUE}--- Starting Garbage Collect Manager ---${NC}"

# Build the nodetool command
CMD="nodetool garbagecollect"
TARGET_DESC="full node"

# Add options
CMD+=" -g $GRANULARITY"
if [[ $JOBS -gt 0 ]]; then
    CMD+=" -j $JOBS"
fi

# Add keyspace/table arguments
if [[ -n "$KEYSPACE" ]]; then
    TARGET_DESC="keyspace '$KEYSPACE'"
    CMD+=" -- $KEYSPACE"
    if [[ -n "$TABLE_LIST" ]]; then
        CMD+=$TABLE_LIST
        # Remove leading space for description
        CLEAN_TABLE_LIST=$(echo "$TABLE_LIST" | sed 's/^ *//g')
        TARGET_DESC="table(s) '$CLEAN_TABLE_LIST' in keyspace '$KEYSPACE'"
    fi
fi

log_message "${BLUE}Target: $TARGET_DESC${NC}"
log_message "${BLUE}Disk path to check: $DISK_CHECK_PATH${NC}"
log_message "${BLUE}Warning usage threshold: $WARNING_THRESHOLD%${NC}"
log_message "${BLUE}Critical usage threshold: $CRITICAL_THRESHOLD%${NC}"
log_message "Command to be executed: $CMD"

# Pre-flight disk space check
log_message "${BLUE}Performing pre-flight disk usage check...${NC}"
if ! /usr/local/bin/disk-health-check.sh -p "$DISK_CHECK_PATH" -w "$WARNING_THRESHOLD" -c "$CRITICAL_THRESHOLD"; then
    log_message "${RED}ERROR: Pre-flight disk usage check failed. Aborting garbage collection to prevent disk space issues.${NC}"
    exit 1
fi
log_message "${GREEN}Disk usage OK. Proceeding.${NC}"

# Pre-flight node state check
log_message "${BLUE}Performing pre-flight node state check...${NC}"
if ! nodetool netstats | grep -q "Mode: NORMAL"; then
    log_message "${YELLOW}ERROR: Node is not in NORMAL mode. It may be streaming, joining, or leaving the cluster.${NC}"
    log_message "Aborting garbage collection. Please wait for the node to become idle."
    nodetool netstats
    exit 1
fi
log_message "${GREEN}Node state is NORMAL. Proceeding.${NC}"

# Execute the command
if $CMD; then
    log_message "${GREEN}--- Garbage Collect Finished Successfully ---${NC}"
    exit 0
else
    GC_EXIT_CODE=$?
    log_message "${RED}ERROR: Garbage collection command failed with exit code $GC_EXIT_CODE.${NC}"
    exit $GC_EXIT_CODE
fi
