#!/bin/bash
# This file is managed by Puppet.
# Wrapper for sstabledump to easily inspect SSTables for a given table.

set -euo pipefail

# --- Config ---
CASSANDRA_DATA_DIR="/var/lib/cassandra/data"

# --- Color Codes ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# --- Logging (to stderr) ---
log_message() {
    echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] $1" >&2
}

# --- Usage ---
usage() {
    log_message "${YELLOW}Usage: $0 -k <keyspace> -t <table> [-n <sstable_number>]${NC}"
    log_message "A wrapper for the 'sstabledump' utility."
    log_message "  -k, --keyspace <name>    The keyspace of the table."
    log_message "  -t, --table <name>       The table to inspect."
    log_message "  -n, --sstable-number <N> (Optional) Dump only a specific SSTable by its generation number."
    log_message "  -h, --help               Show this help message."
    exit 1
}

# --- Argument Parsing ---
KEYSPACE=""
TABLE=""
SSTABLE_NUM=""

while [[ "$#" -gt 0 ]]; do
    case $1 in
        -k|--keyspace) KEYSPACE="$2"; shift ;;
        -t|--table) TABLE="$2"; shift ;;
        -n|--sstable-number) SSTABLE_NUM="$2"; shift ;;
        -h|--help) usage ;;
        *) log_message "${RED}Unknown parameter passed: $1${NC}"; usage ;;
    esac
    shift
done

if [ -z "$KEYSPACE" ] || [ -z "$TABLE" ]; then
    log_message "${RED}ERROR: Both keyspace (-k) and table (-t) are required.${NC}"
    usage
fi

# --- Main Logic ---
log_message "${BLUE}--- Running sstabledump for ${KEYSPACE}.${TABLE} ---${NC}"

# Find the UUID-based directory for the table
TABLE_DIR_UUID=$(find "${CASSANDRA_DATA_DIR}/${KEYSPACE}" -maxdepth 1 -type d -name "${TABLE}-*" 2>/dev/null | head -n 1)

if [ -z "$TABLE_DIR_UUID" ]; then
    log_message "${RED}ERROR: Could not find data directory for table '${TABLE}' in keyspace '${KEYSPACE}'.${NC}"
    exit 1
fi
log_message "Found table data directory: $TABLE_DIR_UUID"

SSTABLE_FILES=()
if [ -n "$SSTABLE_NUM" ]; then
    # Find the specific SSTable data file
    SPECIFIC_FILE=$(find "$TABLE_DIR_UUID" -type f -name "*-${SSTABLE_NUM}-Data.db")
    if [ -z "$SPECIFIC_FILE" ]; then
        log_message "${RED}ERROR: Could not find SSTable with generation number '${SSTABLE_NUM}'.${NC}"
        exit 1
    fi
    SSTABLE_FILES+=("$SPECIFIC_FILE")
else
    # Find all SSTable data files, handle no-match case gracefully
    readarray -d '' -t SSTABLE_FILES < <(find "$TABLE_DIR_UUID" -type f -name '*-Data.db' -print0 2>/dev/null)
fi


if [ ${#SSTABLE_FILES[@]} -eq 0 ]; then
    log_message "${YELLOW}No SSTable data files (*-Data.db) found for this table. Nothing to dump.${NC}"
    exit 0
fi

log_message "Found ${#SSTABLE_FILES[@]} SSTable(s) to dump."

for sstable in "${SSTABLE_FILES[@]}"; do
    log_message "${GREEN}--- Dumping ${sstable} ---${NC}"
    # The output of sstabledump goes to stdout
    if ! sstabledump "$sstable"; then
        log_message "${RED}ERROR: sstabledump failed for file: $sstable${NC}"
    fi
done

log_message "${BLUE}--- sstabledump finished ---${NC}"
