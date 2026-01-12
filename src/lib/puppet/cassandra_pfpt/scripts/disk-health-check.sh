#!/bin/bash

set -euo pipefail

CASSANDRA_DATADIR=/var/lib/cassandra/data
# Aligned with the backup-to-s3.sh script
BACKUP_PREFIX=backup

CLEAR_SNAPSHOTS=false
WARNING_THRESHOLD=60
CRITICAL_THRESHOLD=30

RESET="\e[0m"
## Formatting
# Attributes
BOLD="\e[1m"
COL_MAGENTA="\e[35m"
COL_LIGHT_MAGENTA="\e[95m"
COL_BLUE="\e[34m"
COL_YELLOW="1;31"
COL_RED="\e[31m"

function usage() {
  cat<<EOF
usage: $0 [OPTIONS]

Checks the amount of disk space for '${CASSANDRA_DATADIR}' against given thresholds.

Flags:
   -w INT   Sets the threshold which emits a warning (default: $WARNING_THRESHOLD)
   -c INT   Sets the threshold which is treated as CRITICAL (default: $CRITICAL_THRESHOLD)

   -r       When set, cassandra snapshots will be removed automagically if disk space is low.

Exit code of the script will be:

 0  - If free disk space is below critical and warning threshold.
 1  - If free disk space is below the warning threshold.
 2  - If free disk space is below the critical threshold.
EOF
}

function warning {
  local msg=$@
  # shellcheck disable=SC2059
  printf "${COL_LIGHT_MAGENTA}WARNING: ${msg}${RESET}\n" >&2
}

#
# Print an error message
#
# Usage in a script:
#   error "message"

function error {
  local msg=$@
  # shellcheck disable=SC2059
  printf "${BOLD}${COL_RED}${msg}${RESET}\n" >&2
}

function delete_snapshots {
  local cassandra_datadir=$1

  find "${cassandra_datadir}"/*/*/ -maxdepth 1 -mindepth 1 -type d -name snapshots | while read -r dir; do
    if [[ -n "$(find ${dir} -maxdepth 1 -mindepth 1 -type d -name "${BACKUP_PREFIX}*" | head -n1)" ]]; then
      find "${dir}" -maxdepth 1 -mindepth 1 -type d -name "${BACKUP_PREFIX}*" -exec ls -t1d {} + | while read -r snapshot; do
        snapshot_name=${snapshot##*/}
        printf "\e[35mINFO: Deleting snapshot %s for all keyspaces \e[0m\n" "${snapshot_name}"
        nodetool clearsnapshot -t "${snapshot_name}"
      done
    fi
  done
  # sleep 10 seconds to wait for freed up disk space
  sleep 10
}


#
# Returns the current free disk space of a node in percent
#
# Usage
# disk_free=$(get_free_disk_space)
function get_free_disk_space {
  local mountpoint=$1

  currently_used=$(df "${mountpoint}" --output=pcent | tail -1 | tr -cd '[:digit:]')
  rc=$?
  if [[ -z "$currently_used" ]] || [[ $rc != 0 ]]; then
    error "Failed to get free disk space."
    exit 3
  fi

  echo $(( 100-currently_used ))

  return 0
}
#
# Check the disk space of a node
#
# Usage in a script:
#   if ! has_enough_free_disk_space NODENAME <MOUNTPOINT> <WARN_THRESHOLD> <CRITICAL_THRESHOLD>; then
#      warning "Disk space on $nodename is below threshold
#   fi

function has_enough_free_disk_space {
  local mountpoint=${1:-/}
  local warn_threshold=${2:-30}
  local crit_threshold=${3:-80}

  free_disk_space=$(get_free_disk_space "$mountpoint")

  if [[ $free_disk_space -lt $crit_threshold ]]; then
    error "Free disk space for '$mountpoint' is below ${crit_threshold} %%"
    return 2
  fi

  if [[ $free_disk_space -lt $warn_threshold ]]; then
    warning "Free disk space for '$mountpoint' is below ${warn_threshold}%%."
    return 1
  fi

  return 0
}

set -x
while getopts "hw:c:r" arg; do
  case $arg in
    h)
      usage
      ;;
    w)
      WARNING_THRESHOLD=${OPTARG}
      ;;
    c)
      CRITICAL_THRESHOLD=${OPTARG}
      ;;
    r)
      CLEAR_SNAPSHOTS=true
      ;;
    default)
      usage
      echo "invalid options"
      exit 1
      ;;
  esac
done
shift $((OPTIND-1))
set +x

MOUNTPOINT=$CASSANDRA_DATADIR

exit_code=2
if has_enough_free_disk_space "$MOUNTPOINT" "$WARNING_THRESHOLD" "$CRITICAL_THRESHOLD"; then
  disk_free=$(get_free_disk_space "$MOUNTPOINT")
  printf "Disk space is OK (free disk space: %d %% is above %d %%)\n" "$disk_free" "$CRITICAL_THRESHOLD"
  exit_code=0
else
  if [[ $CLEAR_SNAPSHOTS == "true" ]]; then
    warning "Deleting snapshots to gain some free space."
    delete_snapshots "$MOUNTPOINT"
    sleep 10
    if has_enough_free_disk_space "$MOUNTPOINT" "$WARNING_THRESHOLD" "$CRITICAL_THRESHOLD"; then
      printf "Disk space is now OK (free disk space: %d is below %d %%)\n" "$disk_free" "$CRITICAL_THRESHOLD"
      exit_code=1
    fi
  fi
fi

exit "$exit_code"
