#!/bin/bash

set -euo pipefail

# These are defaults if not passed via flags.
CASSANDRA_DATADIR=/var/lib/cassandra/data
WARNING_THRESHOLD=30
CRITICAL_THRESHOLD=15

# Color codes
RESET="\e[0m"
BOLD="\e[1m"
COL_RED="\e[31m"
COL_YELLOW="\e[33m"

function usage() {
  cat<<EOF
usage: $0 [OPTIONS]

Checks the available disk space for a directory (defaults to '$CASSANDRA_DATADIR') against given thresholds.
Thresholds are percentages of FREE space.

Flags:
   -p PATH  Path to check disk space for. Default: $CASSANDRA_DATADIR
   -w INT   Warning threshold (percent free). Default: $WARNING_THRESHOLD
   -c INT   Critical threshold (percent free). Default: $CRITICAL_THRESHOLD
   -h       Show this help message.

Exit Codes:
 0: Disk space is sufficient.
 1: Disk space is below the warning threshold.
 2: Disk space is below the critical threshold.
 3: Script failed to get disk space information.
EOF
}

function warning() {
  local msg="$@"
  printf "$BOLD$COL_YELLOW""WARNING: %s""$RESET\n" "$msg" >&2
}

function error() {
  local msg="$@"
  printf "$BOLD$COL_RED""ERROR: %s""$RESET\n" "$msg" >&2
}

function get_free_disk_space() {
  local mountpoint="$1"
  local used_percent
  
  used_percent=$(df "$mountpoint" --output=pcent | tail -1 | tr -cd '[:digit:]')
  rc=$?

  if [[ -z "$used_percent" ]] || [[ $rc != 0 ]]; then
    error "Failed to get disk space for path '$mountpoint'."
    exit 3
  fi

  echo $(( 100 - used_percent ))
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

free_space=$(get_free_disk_space "$CASSANDRA_DATADIR")
exit_code=$?

if [[ $free_space -lt $CRITICAL_THRESHOLD ]]; then
  error "Free disk space for '$CASSANDRA_DATADIR' is $free_space%, which is below the critical threshold of $CRITICAL_THRESHOLD%."
  exit 2
fi

if [[ $free_space -lt $WARNING_THRESHOLD ]]; then
  warning "Free disk space for '$CASSANDRA_DATADIR' is $free_space%, which is below the warning threshold of $WARNING_THRESHOLD%."
  exit 1
fi

printf "OK: Free disk space for '$CASSANDRA_DATADIR' is $free_space%%, which is above all thresholds.\n"
exit 0
