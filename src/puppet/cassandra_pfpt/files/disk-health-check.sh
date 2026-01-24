#!/bin/bash
# This file is managed by Puppet.
set -euo pipefail

# These are defaults if not passed via flags.
CASSANDRA_DATADIR=/var/lib/cassandra/data
WARNING_THRESHOLD=85
CRITICAL_THRESHOLD=95

# Color codes
RESET="\e[0m"
BOLD="\e[1m"
COL_RED="\e[31m"
COL_YELLOW="\e[33m"

function usage() {
  cat<<EOF
usage: $0 [OPTIONS]

Checks the disk usage for a directory (defaults to '$CASSANDRA_DATADIR') against given thresholds.
Thresholds are percentages of USED space.

Flags:
   -p PATH  Path to check disk usage for. Default: $CASSANDRA_DATADIR
   -w INT   Warning threshold (percent used). Default: $WARNING_THRESHOLD
   -c INT   Critical threshold (percent used). Default: $CRITICAL_THRESHOLD
   -h       Show this help message.

Exit Codes:
 0: Disk usage is within acceptable limits.
 1: Disk usage is above the warning threshold.
 2: Disk usage is above the critical threshold.
 3: Script failed to get disk space information.
EOF
}

function warning() {
  local msg="$@"
  # Use printf with %s to avoid issues with '%' in the message
  printf -- "${BOLD}${COL_YELLOW}WARNING: %s${RESET}\n" "$msg" >&2
}

function error() {
  local msg="$@"
  # Use printf with %s to avoid issues with '%' in the message
  printf -- "${BOLD}${COL_RED}ERROR: %s${RESET}\n" "$msg" >&2
}

function get_used_disk_space() {
  local mountpoint="$1"
  local used_percent
  
  used_percent=$(df "$mountpoint" --output=pcent | tail -1 | tr -cd '[:digit:]')
  rc=$?

  if [[ -z "$used_percent" ]] || [[ $rc != 0 ]]; then
    error "Failed to get disk space for path '$mountpoint'."
    exit 3
  fi

  echo "$used_percent"
}

# --- Main Logic ---
while getopts "hp:w:c:" arg; do
  case $arg in
    h)
      usage
      exit 0
      ;;
    p)
      CASSANDRA_DATADIR=$OPTARG
      ;;
    w)
      WARNING_THRESHOLD=$OPTARG
      ;;
    c)
      CRITICAL_THRESHOLD=$OPTARG
      ;;
    *)
      usage
      exit 1
      ;;
  esac
done

used_space=$(get_used_disk_space "$CASSANDRA_DATADIR")
exit_code=$?

if [[ $used_space -gt $CRITICAL_THRESHOLD ]]; then
  error "Disk usage for '$CASSANDRA_DATADIR' is $used_space%, which is above the critical threshold of $CRITICAL_THRESHOLD%."
  exit 2
fi

if [[ $used_space -gt $WARNING_THRESHOLD ]]; then
  warning "Disk usage for '$CASSANDRA_DATADIR' is $used_space%, which is above the warning threshold of $WARNING_THRESHOLD%."
  exit 1
fi

printf -- "OK: Disk usage for '$CASSANDRA_DATADIR' is %s%%, which is below all thresholds.\n" "$used_space"
exit 0
