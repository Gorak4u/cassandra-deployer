#!/bin/bash
# This file is managed by Puppet.
# Scans and reports on tombstone counts across keyspaces and tables.

set -euo pipefail

# --- Color Codes ---
RED='\e[0;31m'
GREEN='\e[0;32m'
YELLOW='\e[1;33m'
BLUE='\e[0;34m'
CYAN='\e[0;36m'
BOLD='\e[1m'
NC='\e[0m'

# --- Argument Parsing ---
KEYSPACE_FILTER="${1:-}"
SORT_COLUMN=4 # Default to sorting by Average Tombstones

usage() {
    echo "Usage: $0 [keyspace_name]"
    echo "  Scans and reports on tombstone statistics for all tables."
    echo "  If [keyspace_name] is provided, results will be filtered to that keyspace."
    exit 1
}

if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    usage
fi

# --- Main Logic ---
echo -e "${BLUE}--- Scanning Tombstone Statistics ---${NC}"
if [ -n "$KEYSPACE_FILTER" ]; then
    echo -e "${BLUE}Filtering for keyspace: ${BOLD}$KEYSPACE_FILTER${NC}"
fi

# Run nodetool and capture output
if ! TABSTATS_OUTPUT=$(nodetool tablestats 2>/dev/null); then
    echo -e "${RED}ERROR: Failed to run 'nodetool tablestats'. Is Cassandra running?${NC}" >&2
    exit 1
fi

# Use awk to parse the multi-line output into a single line per table
PARSED_DATA=$(echo "$TABSTATS_OUTPUT" | awk -v filter="$KEYSPACE_FILTER" '
    BEGIN {
        ks = "N/A";
        OFS = "\t"; # Use tab as a separator for `column` command
    }
    /^[Kk]eyspace/ {
        # New keyspace section
        ks = $NF;
    }
    /Table: / {
        # A new table section is starting. If we have data for a previous table, print it.
        if (table_name != "") print_table();
        
        # Reset and capture the new table name
        table_name = $NF;
        avg_tomb = "0.0";
        max_tomb = "0.0";
        avg_live = "0.0";
    }
    /Average tombstones per slice/ {
        avg_tomb = $NF;
    }
    /Maximum tombstones per slice/ {
        max_tomb = $NF;
    }
    /Average live cells per slice/ {
        avg_live = $NF;
    }
    END {
        # Print the very last table captured
        if (table_name != "") print_table();
    }
    function print_table() {
        if (filter == "" || ks == filter) {
             printf "%s\t%s\t%.1f\t%.1f\t%.1f\n", ks, table_name, avg_live, avg_tomb, max_tomb;
        }
    }
')

if [ -z "$PARSED_DATA" ]; then
    echo -e "${YELLOW}No table statistics found. The cluster might be empty or the keyspace filter may not match.${NC}"
    exit 0
fi

# --- Header ---
HEADER=$(printf "KEYSPACE\tTABLE\tAVG_LIVE\tAVG_TOMBS\tMAX_TOMBS")

# --- Sort and Display ---
# Sort by the average tombstones column (4th column), numerically, in reverse order.
# Then pipe to `column` for nice formatting.
{
    echo "$HEADER";
    echo "$PARSED_DATA" | sort -k$SORT_COLUMN -nr;
} | column -t -s $'\t'

echo
echo -e "${YELLOW}Report sorted by ${BOLD}AVG_TOMBS${NC} (Average tombstones per slice)."
echo -e "${YELLOW}High values here often indicate inefficient query patterns or needed cleanup.${NC}"
echo

exit 0
