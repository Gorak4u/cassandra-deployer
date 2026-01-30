#!/bin/bash
# This file is managed by Puppet.
# Scans and reports on tombstone counts across keyspaces and tables.

set -euo pipefail

# --- Config ---
CASSANDRA_DATA_DIR="/var/lib/cassandra/data"

# --- Color Codes ---
RED='\e[0;31m'
GREEN='\e[0;32m'
YELLOW='\e[1;33m'
BLUE='\e[0;34m'
CYAN='\e[0;36m'
BOLD='\e[1m'
NC='\e[0m'

# --- Script State ---
KEYSPACE=""
TABLE=""
SORT_COLUMN=4 # Default to sorting by Average Tombstones

# --- Logging (to stderr) ---
log_error() { echo -e "${RED}ERROR: $1${NC}" >&2; }
log_info() { echo -e "${BLUE}$1${NC}"; }
log_warn() { echo -e "${YELLOW}$1${NC}"; }

# --- Usage ---
usage() {
    echo "Usage: $0 [-k <keyspace>] [-t <table>]"
    echo ""
    echo "A powerful tombstone analysis tool for Cassandra."
    echo ""
    echo "Modes:"
    echo "  Overview (default):"
    echo "    Run without arguments to see a cluster-wide overview of tombstone statistics for all tables."
    echo "    Example: $0"
    echo ""
    echo "  Filter by Keyspace:"
    echo "    Use -k to filter the overview to a single keyspace."
    echo "    Example: $0 -k my_app"
    echo ""
    echo "  Deep Dive (per-SSTable analysis):"
    echo "    Use -k and -t together to perform a detailed scan of every SSTable for a specific table."
    echo "    This shows which data files have the most droppable tombstones."
    echo "    Example: $0 -k my_app -t users"
    echo ""
    echo "Options:"
    echo "  -h, --help    Show this help message."
    exit 1
}

# --- Argument Parsing ---
while getopts ":k:t:h" opt; do
  case ${opt} in
    k) KEYSPACE=$OPTARG ;;
    t) TABLE=$OPTARG ;;
    h) usage ;;
    \?) log_error "Invalid option: -$OPTARG"; usage ;;
  esac
done

# --- Function for Deep Dive Mode ---
run_deep_dive() {
    log_info "--- Deep Dive Tombstone Analysis for ${KEYSPACE}.${TABLE} ---"
    
    if ! command -v sstablemetadata &> /dev/null; then
        log_error "'sstablemetadata' command not found. Cannot perform deep dive. Is cassandra-tools installed?"
        exit 1
    fi

    local TABLE_DIR_UUID
    TABLE_DIR_UUID=$(find "${CASSANDRA_DATA_DIR}/${KEYSPACE}" -maxdepth 1 -type d -name "${TABLE}-*" 2>/dev/null | head -n 1)

    if [ -z "$TABLE_DIR_UUID" ]; then
        log_error "Could not find data directory for table '${TABLE}' in keyspace '${KEYSPACE}'."
        exit 1
    fi

    local SSTABLE_FILES=()
    readarray -d '' -t SSTABLE_FILES < <(find "$TABLE_DIR_UUID" -type f -name '*-Data.db' -print0 2>/dev/null)

    if [ ${#SSTABLE_FILES[@]} -eq 0 ]; then
        log_warn "No SSTable data files (*-Data.db) found for this table."
        exit 0
    fi
    
    log_info "Analyzing ${#SSTABLE_FILES[@]} SSTable(s)..."

    local HEADER
    HEADER=$(printf "SSTABLE_NAME\tSIZE(MB)\tDROPPABLE_TOMBSTONES\tLEVEL")
    
    local ALL_STATS=()
    for sstable in "${SSTABLE_FILES[@]}"; do
        local METADATA
        METADATA=$(sstablemetadata "$sstable")
        
        local FILENAME
        FILENAME=$(basename "$sstable")
        local SIZE_BYTES
        SIZE_BYTES=$(echo "$METADATA" | grep "Total length:" | awk '{print $3}')
        local SIZE_MB=$((SIZE_BYTES / 1024 / 1024))
        local TOMBSTONES
        TOMBSTONES=$(echo "$METADATA" | grep "Estimated droppable tombstones:" | awk '{print $4}')
        local LEVEL
        LEVEL=$(echo "$METADATA" | grep "SSTable level:" | awk '{print $3}')
        
        # Ensure values are numeric, default to 0 if not
        SIZE_MB=${SIZE_MB:-0}
        TOMBSTONES=${TOMBSTONES:-0.0}
        LEVEL=${LEVEL:-0}

        ALL_STATS+=("$(printf "%s\t%s\t%s\t%s" "$FILENAME" "$SIZE_MB" "$TOMBSTONES" "$LEVEL")")
    done

    {
        echo "$HEADER";
        # Sort by droppable tombstones (col 3), numerically, descending
        printf "%s\n" "${ALL_STATS[@]}" | sort -k3 -nr;
    } | column -t -s $'\t'

    echo
    log_warn "Report sorted by ${BOLD}DROPPABLE_TOMBSTONES${NC}."
    log_warn "These are estimates. High values indicate SSTables that would benefit from compaction."
}

# --- Function for Overview Mode ---
run_overview() {
    log_info "--- Scanning Cluster-Wide Tombstone Statistics ---"
    if [ -n "$KEYSPACE" ]; then
        log_info "Filtering for keyspace: ${BOLD}$KEYSPACE${NC}"
    fi

    # Run nodetool and capture output
    local TABSTATS_OUTPUT
    if ! TABSTATS_OUTPUT=$(nodetool tablestats 2>/dev/null); then
        log_error "Failed to run 'nodetool tablestats'. Is Cassandra running?"
        exit 1
    fi

    local PARSED_DATA
    PARSED_DATA=$(echo "$TABSTATS_OUTPUT" | awk -v filter="$KEYSPACE" '
        BEGIN {
            ks = "N/A";
            OFS = "\t"; # Use tab as a separator for `column` command
        }
        /^[Kk]eyspace/ {
            ks = $NF;
        }
        /Table: / {
            if (table_name != "") print_table();
            table_name = $NF;
            avg_tomb = "0.0";
            max_tomb = "0.0";
            avg_live = "0.0";
        }
        /Average tombstones per slice/ { avg_tomb = $NF; }
        /Maximum tombstones per slice/ { max_tomb = $NF; }
        /Average live cells per slice/ { avg_live = $NF; }
        END {
            if (table_name != "") print_table();
        }
        function print_table() {
            if (filter == "" || ks == filter) {
                 printf "%s\t%s\t%.1f\t%.1f\t%.1f\n", ks, table_name, avg_live, avg_tomb, max_tomb;
            }
        }
    ')

    if [ -z "$PARSED_DATA" ]; then
        log_warn "No table statistics found. The cluster might be empty or the keyspace filter may not match."
        exit 0
    fi

    local HEADER
    HEADER=$(printf "KEYSPACE\tTABLE\tAVG_LIVE\tAVG_TOMBS\tMAX_TOMBS")

    {
        echo "$HEADER";
        echo "$PARSED_DATA" | sort -k$SORT_COLUMN -nr;
    } | column -t -s $'\t'

    echo
    log_warn "Report sorted by ${BOLD}AVG_TOMBS${NC} (Average tombstones per slice)."
    log_warn "To investigate a specific table, run: $0 -k <keyspace> -t <table>"
}

# --- Main Logic ---

if [[ -n "$KEYSPACE" && -n "$TABLE" ]]; then
    run_deep_dive
elif [[ -n "$TABLE" && -z "$KEYSPACE" ]]; then
    log_error "The -t (table) flag requires the -k (keyspace) flag to be set."
    usage
else
    # This handles both the no-argument case and the -k only case.
    run_overview
fi

exit 0
