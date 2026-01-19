
export const scripts = {
      'cassandra-upgrade-precheck.sh': '#!/bin/bash\\n# Placeholder for cassandra-upgrade-precheck.sh\\necho "Cassandra Upgrade Pre-check Script"',
      'cluster-health.sh': '#!/bin/bash\\nnodetool status',
      'repair-node.sh': '#!/bin/bash\\nnodetool repair -pr',
      'drain-node.sh': '#!/bin/bash\\nnodetool drain',
      'decommission-node.sh': `#!/bin/bash
# Securely decommissions a Cassandra node from the cluster.

log_message() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

log_message "INFO: This script will decommission the local Cassandra node."
log_message "This process will stream all of its data to other nodes in the cluster."
log_message "It cannot be undone."
log_message "Are you sure you want to proceed? Type 'yes' to confirm."

read -r confirmation

if [ "$confirmation" != "yes" ]; then
  log_message "Aborted. Node was not decommissioned."
  exit 0
fi

log_message "Starting nodetool decommission..."
nodetool decommission

DECOMMISSION_STATUS=$?

if [ $DECOMMISSION_STATUS -eq 0 ]; then
  log_message "SUCCESS: Nodetool decommission completed successfully."
  log_message "It is now safe to shut down the cassandra service and turn off this machine."
  exit 0
else
  log_message "ERROR: Nodetool decommission FAILED with exit code $DECOMMISSION_STATUS."
  log_message "Check the system logs for more information. Do NOT shut down this node until the issue is resolved."
  exit 1
fi
`,
      'cleanup-node.sh': '#!/bin/bash\\necho "Cleanup Node Script"',
      'take-snapshot.sh': '#!/bin/bash\\necho "Take Snapshot Script"',
      'rebuild-node.sh': '#!/bin/bash\\necho "Rebuild Node Script"',
      'garbage-collect.sh': '#!/bin/bash\\necho "Garbage Collect Script"',
      'assassinate-node.sh': `#!/bin/bash
# Assassinate a node. Use with extreme caution.

log_message() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

NODE_IP="$1"

if [ -z "$NODE_IP" ]; then
  log_message "Error: Node IP address must be provided as an argument."
  log_message "Usage: $0 <ip_address_of_dead_node>"
  exit 1
fi

log_message "WARNING: Attempting to assassinate node at IP: $NODE_IP. This will remove it from the cluster."
log_message "Are you sure you want to proceed? Type 'yes' to confirm."
read confirmation

if [ "$confirmation" != "yes" ]; then
  log_message "Aborted."
  exit 0
fi

nodetool assassinate "$NODE_IP"
ASSASSINATE_STATUS=$?

if [ $ASSASSINATE_STATUS -eq 0 ]; then
  log_message "Nodetool assassinate of $NODE_IP completed successfully."
  exit 0
else
  log_message "Nodetool assassinate of $NODE_IP FAILED with exit code $ASSASSINATE_STATUS."
  exit 1
fi
`,
      'upgrade-sstables.sh': '#!/bin/bash\\necho "Upgrade SSTables Script"',
      'backup-to-s3.sh': `#!/bin/bash
# Performs a snapshot and mocks S3 upload.

log_message() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# --- Configuration ---
BUCKET_NAME="your-s3-backup-bucket"
CASSANDRA_DATA_DIR="/var/lib/cassandra/data" # Ensure this is correct
CASSANDRA_COMMITLOG_DIR="/var/lib/cassandra/commitlog" # Optional, usually not backed up with data
SNAPSHOT_TAG="backup_$(date +%Y%m%d%H%M%S)"
HOSTNAME=$(hostname -s)
BACKUP_TEMP_DIR="/tmp/cassandra_backup_\${SNAPSHOT_TAG}"

# --- Functions ---
cleanup_temp() {
  log_message "Cleaning up temporary directory: \${BACKUP_TEMP_DIR}"
  rm -rf "\${BACKUP_TEMP_DIR}"
}

# --- Main Logic ---
log_message "Starting Cassandra backup to S3 process..."

# 1. Take a snapshot
log_message "Taking Cassandra snapshot with tag: \${SNAPSHOT_TAG}..."
nodetool snapshot -t "\${SNAPSHOT_TAG}"
if [ $? -ne 0 ]; then
  log_message "ERROR: Failed to take Cassandra snapshot."
  exit 1
fi
log_message "Snapshot taken successfully."

# Find snapshot directory. This path might vary.
# Example: /var/lib/cassandra/data/keyspace/table/snapshots/TAG
SNAPSHOT_ROOT_DIR="\${CASSANDRA_DATA_DIR}"

# Prepare temporary directory for tarball
mkdir -p "\${BACKUP_TEMP_DIR}" || { log_message "ERROR: Failed to create temp backup directory."; exit 1; }

log_message "Creating tar.gz archive of snapshot data from \${SNAPSHOT_ROOT_DIR} to \${BACKUP_TEMP_DIR}/\${HOSTNAME}_cassandra_snapshot_\${SNAPSHOT_TAG}.tar.gz ..."
# Find all snapshot directories for the current tag and tar them
find "\${SNAPSHOT_ROOT_DIR}" -type d -name "\${SNAPSHOT_TAG}" -exec tar -czvf "\${BACKUP_TEMP_DIR}/\${HOSTNAME}_cassandra_snapshot_\${SNAPSHOT_TAG}.tar.gz" -C {} . \\;
if [ $? -ne 0 ]; then
  log_message "ERROR: Failed to create tar.gz archive of snapshot data."
  cleanup_temp
  exit 1
fi
log_message "Snapshot data archived successfully."

# 3. Upload to S3 (mocked command)
UPLOAD_PATH="s3://\${BUCKET_NAME}/cassandra/\${HOSTNAME}/\${SNAPSHOT_TAG}/\${HOSTNAME}_cassandra_snapshot_\${SNAPSHOT_TAG}.tar.gz"
log_message "Mocking S3 upload command:"
echo "aws s3 cp \${BACKUP_TEMP_DIR}/\${HOSTNAME}_cassandra_snapshot_\${SNAPSHOT_TAG}.tar.gz \${UPLOAD_PATH}"
# In a real scenario, you'd run:
# aws s3 cp "\${BACKUP_TEMP_DIR}/\${HOSTNAME}_cassandra_snapshot_\${SNAPSHOT_TAG}.tar.gz" "\${UPLOAD_PATH}"
# if [ $? -ne 0 ]; then
#   log_message "ERROR: Failed to upload backup to S3."
#   cleanup_temp
#   exit 1
# # fi
log_message "S3 upload mocked successfully. In a real scenario, this would be uploaded."

# 4. Clear snapshots (optional, do AFTER successful upload)
# log_message "Clearing snapshots with tag: \${SNAPSHOT_TAG}..."
# nodetool clearsnapshot -t "\${SNAPSHOT_TAG}"
# if [ $? -ne 0 ]; then
# #   log_message "WARNING: Failed to clear snapshot \${SNAPSHOT_TAG}."
# fi

cleanup_temp
log_message "Cassandra backup to S3 process completed."
exit 0
`,
      'prepare-replacement.sh': '#!/bin/bash\\necho "Prepare Replacement Script"',
      'version-check.sh': '#!/bin/bash\\necho "Version Check Script"',
      'cassandra_range_repair.py': '#!/usr/bin/env python3\\nprint("Cassandra Range Repair Python Script")',
      'range-repair.sh': '#!/bin/bash\\necho "Range Repair Script"',
      'robust_backup.sh': '#!/bin/bash\\necho "Robust Backup Script Placeholder"',
      'restore_from_backup.sh': '#!/bin/bash\\necho "Restore from Backup Script Placeholder"',
      'node_health_check.sh': '#!/bin/bash\\necho "Node Health Check Script Placeholder"',
      'rolling_restart.sh': '#!/bin/bash\\necho "Rolling Restart Script Placeholder"',
      'disk-health-check.sh': `#!/bin/bash

set -euo pipefail

CASSANDRA_DATADIR=/var/lib/cassandra/data
# Aligned with the backup-to-s3.sh script
BACKUP_PREFIX=backup

CLEAR_SNAPSHOTS=false
WARNING_THRESHOLD=60
CRITICAL_THRESHOLD=30

RESET="\\e[0m"
## Formatting
# Attributes
BOLD="\\e[1m"
COL_MAGENTA="\\e[35m"
COL_LIGHT_MAGENTA="\\e[95m"
COL_BLUE="\\e[34m"
COL_YELLOW="1;31"
COL_RED="\\e[31m"

function usage() {
  cat<<EOF
usage: $0 [OPTIONS]

Checks the amount of disk space for '\${CASSANDRA_DATADIR}' against given thresholds.

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
  printf "\\\${COL_LIGHT_MAGENTA}WARNING: \${msg}\\\${RESET}\\n" >&2
}

#
# Print an error message
#
# Usage in a script:
#   error "message"

function error {
  local msg=$@
  # shellcheck disable=SC2059
  printf "\\\${BOLD}\\\${COL_RED}\${msg}\\\${RESET}\\n" >&2
}

function delete_snapshots {
  local cassandra_datadir=$1

  find "\${cassandra_datadir}"/*/*/ -maxdepth 1 -mindepth 1 -type d -name snapshots | while read -r dir; do
    if [[ -n "$(find \${dir} -maxdepth 1 -mindepth 1 -type d -name "\\\${BACKUP_PREFIX}*" | head -n1)" ]]; then
      find "\${dir}" -maxdepth 1 -mindepth 1 -type d -name "\\\${BACKUP_PREFIX}*" -exec ls -t1d {} + | while read -r snapshot; do
        snapshot_name=\${snapshot##*/}
        printf "\\e[35mINFO: Deleting snapshot %s for all keyspaces \\e[0m\\n" "\${snapshot_name}"
        nodetool clearsnapshot -t "\${snapshot_name}"
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

  currently_used=$(df "\${mountpoint}" --output=pcent | tail -1 | tr -cd '[:digit:]')
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
  local mountpoint=\${1:-/}
  local warn_threshold=\${2:-30}
  local crit_threshold=\${3:-80}

  free_disk_space=$(get_free_disk_space "$mountpoint")

  if [[ $free_disk_space -lt $crit_threshold ]]; then
    error "Free disk space for '$mountpoint' is below \\\${crit_threshold} %%"
    return 2
  fi

  if [[ $free_disk_space -lt $warn_threshold ]]; then
    warning "Free disk space for '$mountpoint' is below \\\${warn_threshold}%%."
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
      WARNING_THRESHOLD=\${OPTARG}
      ;;
    c)
      CRITICAL_THRESHOLD=\${OPTARG}
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
  printf "Disk space is OK (free disk space: %d %% is above %d %%)\\n" "$disk_free" "$CRITICAL_THRESHOLD"
  exit_code=0
else
  if [[ $CLEAR_SNAPSHOTS == "true" ]]; then
    warning "Deleting snapshots to gain some free space."
    delete_snapshots "$MOUNTPOINT"
    sleep 10
    if has_enough_free_disk_space "$MOUNTPOINT" "$WARNING_THRESHOLD" "$CRITICAL_THRESHOLD"; then
      printf "Disk space is now OK (free disk space: %d is below %d %%)\\n" "$disk_free" "$CRITICAL_THRESHOLD"
      exit_code=1
    fi
  fi
fi

exit "$exit_code"
`,
    };
