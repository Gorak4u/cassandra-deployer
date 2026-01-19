
export const scripts = {
      'cassandra-upgrade-precheck.sh': '#!/bin/bash\\n# Placeholder for cassandra-upgrade-precheck.sh\\necho "Cassandra Upgrade Pre-check Script"',
      'cluster-health.sh': '#!/bin/bash\\nnodetool status',
      'repair-node.sh': '#!/bin/bash\\nnodetool repair -pr',
      'drain-node.sh': '#!/bin/bash\\nnodetool drain',
      'decommission-node.sh': `#!/bin/bash
# Securely decommissions a Cassandra node from the cluster.

log_message() {
  echo "[\\${'$'}(date +'%Y-%m-%d %H:%M:%S')] \\${'$'}1"
}

log_message "INFO: This script will decommission the local Cassandra node."
log_message "This process will stream all of its data to other nodes in the cluster."
log_message "It cannot be undone."
log_message "Are you sure you want to proceed? Type 'yes' to confirm."

read -r confirmation

if [ "\\${'$'}confirmation" != "yes" ]; then
  log_message "Aborted. Node was not decommissioned."
  exit 0
fi

log_message "Starting nodetool decommission..."
nodetool decommission

DECOMMISSION_STATUS=\\${'$'}?

if [ \\${'$'}DECOMMISSION_STATUS -eq 0 ]; then
  log_message "SUCCESS: Nodetool decommission completed successfully."
  log_message "It is now safe to shut down the cassandra service and turn off this machine."
  exit 0
else
  log_message "ERROR: Nodetool decommission FAILED with exit code \\${'$'}DECOMMISSION_STATUS."
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
  echo "[\\${'$'}(date +'%Y-%m-%d %H:%M:%S')] \\${'$'}1"
}

NODE_IP="\\${'$'}1"

if [ -z "\\${'$'}NODE_IP" ]; then
  log_message "Error: Node IP address must be provided as an argument."
  log_message "Usage: \\${'$'}0 <ip_address_of_dead_node>"
  exit 1
fi

log_message "WARNING: Attempting to assassinate node at IP: \\${'$'}NODE_IP. This will remove it from the cluster."
log_message "Are you sure you want to proceed? Type 'yes' to confirm."
read confirmation

if [ "\\${'$'}confirmation" != "yes" ]; then
  log_message "Aborted."
  exit 0
fi

nodetool assassinate "\\${'$'}NODE_IP"
ASSASSINATE_STATUS=\\${'$'}?

if [ \\${'$'}ASSASSINATE_STATUS -eq 0 ]; then
  log_message "Nodetool assassinate of \\${'$'}NODE_IP completed successfully."
  exit 0
else
  log_message "Nodetool assassinate of \\${'$'}NODE_IP FAILED with exit code \\${'$'}ASSASSINATE_STATUS."
  exit 1
fi
`,
      'upgrade-sstables.sh': '#!/bin/bash\\necho "Upgrade SSTables Script"',
      'full-backup-to-s3.sh': `#!/bin/bash
# Performs a full snapshot backup and uploads it to a simulated S3 bucket.

set -euo pipefail

# --- Configuration from JSON file ---
CONFIG_FILE="/etc/backup/config.json"

# --- Logging ---
# This function will be defined after LOG_FILE is sourced from config
log_message() {
  echo "[\\${'$'}(date +'%Y-%m-%d %H:%M:%S')] \\${'$'}1" | tee -a "\\${'$'}{LOG_FILE}"
}

# Check for config file and jq
if ! command -v jq &> /dev/null; then
  # Cannot use log_message here as LOG_FILE is not yet defined
  echo "[\\${'$'}(date +'%Y-%m-%d %H:%M:%S')] ERROR: jq is not installed. Please install jq to continue."
  exit 1
fi
if [ ! -f "\\${'$'}CONFIG_FILE" ]; then
  echo "[\\${'$'}(date +'%Y-%m-%d %H:%M:%S')] ERROR: Backup configuration file not found at \\${'$'}CONFIG_FILE"
  exit 1
fi

# Source configuration from JSON
S3_BUCKET_NAME=\\${'$'}(jq -r '.s3_bucket_name' "\\${'$'}CONFIG_FILE")
CASSANDRA_DATA_DIR=\\${'$'}(jq -r '.cassandra_data_dir' "\\${'$'}CONFIG_FILE")
LOG_FILE=\\${'$'}(jq -r '.full_backup_log_file' "\\${'$'}CONFIG_FILE")

# Validate sourced config
if [ -z "\\${'$'}S3_BUCKET_NAME" ] || [ -z "\\${'$'}CASSANDRA_DATA_DIR" ] || [ -z "\\${'$'}LOG_FILE" ]; then
  echo "[\\${'$'}(date +'%Y-%m-%d %H:%M:%S')] ERROR: One or more required configuration values are missing from \\${'$'}CONFIG_FILE"
  exit 1
fi

# --- Static Configuration ---
SNAPSHOT_TAG="full_snapshot_\\${'$'}(date +%Y%m%d%H%M%S)"
HOSTNAME=\\${'$'}(hostname -s)
BACKUP_ROOT_DIR="/tmp/cassandra_backups"
BACKUP_TEMP_DIR="\\${'$'}{BACKUP_ROOT_DIR}/\\${'$'}{HOSTNAME}_\\${'$'}{SNAPSHOT_TAG}"


# --- Cleanup Functions ---
cleanup_temp_dir() {
  if [ -d "\\${'$'}{BACKUP_TEMP_DIR}" ]; then
    log_message "Cleaning up temporary directory: \\${'$'}{BACKUP_TEMP_DIR}"
    rm -rf "\\${'$'}{BACKUP_TEMP_DIR}"
  fi
}

# --- Main Logic ---
if [ "\\${'$'}(id -u)" -ne 0 ]; then
  log_message "ERROR: This script must be run as root."
  exit 1
fi

trap cleanup_temp_dir EXIT

log_message "--- Starting Full Cassandra Snapshot Backup Process ---"
log_message "S3 Bucket: \\${'$'}{S3_BUCKET_NAME}"
log_message "Snapshot Tag: \\${'$'}{SNAPSHOT_TAG}"

# 1. Create temporary directory structure
mkdir -p "\\${'$'}{BACKUP_TEMP_DIR}" || { log_message "ERROR: Failed to create temp backup directories."; exit 1; }

# 2. Take a node-local snapshot
log_message "Taking full snapshot with tag: \\${'$'}{SNAPSHOT_TAG}..."
if ! nodetool snapshot -t "\\${'$'}{SNAPSHOT_TAG}"; then
  log_message "ERROR: Failed to take Cassandra snapshot. Aborting backup."
  exit 1
fi
log_message "Full snapshot taken successfully."

# 3. Collect snapshot file paths
find "\\${'$'}{CASSANDRA_DATA_DIR}" -type f -path "*/snapshots/\\${'$'}{SNAPSHOT_TAG}/*" > "\\${'$'}{BACKUP_TEMP_DIR}/snapshot_files.list"

# 4. Archive the files
TARBALL_PATH="\\${'$'}{BACKUP_ROOT_DIR}/\\${'$'}{HOSTNAME}_\\${'$'}{SNAPSHOT_TAG}.tar.gz"
log_message "Archiving snapshot data to \\${'$'}{TARBALL_PATH}..."

if [ ! -s "\\${'$'}{BACKUP_TEMP_DIR}/snapshot_files.list" ]; then
    log_message "WARNING: No snapshot files found. The cluster may be empty. Aborting backup."
    nodetool clearsnapshot -t "\\${'$'}{SNAPSHOT_TAG}"
    exit 0
fi

tar -czf "\\${'$'}{TARBALL_PATH}" -P -T "\\${'$'}{BACKUP_TEMP_DIR}/snapshot_files.list"

# 5. Archive the schema
log_message "Backing up schema..."
SCHEMA_FILE="\\${'$'}{BACKUP_TEMP_DIR}/schema.cql"
timeout 30 cqlsh -e "DESCRIBE SCHEMA;" > "\\${'$'}{SCHEMA_FILE}"
if [ \\${'$'}? -ne 0 ]; then
  log_message "WARNING: Failed to dump schema. Backup will continue without it."
else
  # Add schema to the existing tarball
  tar -rf "\\${'$'}{TARBALL_PATH}" -C "\\${'$'}{BACKUP_TEMP_DIR}" "schema.cql"
  log_message "Schema appended to archive."
fi

# 6. Upload to S3 (mocked)
UPLOAD_PATH="s3://\\${'$'}{S3_BUCKET_NAME}/cassandra/\\${'$'}{HOSTNAME}/full/\\${'$'}{SNAPSHOT_TAG}.tar.gz"
log_message "Simulating S3 upload to: \\${'$'}{UPLOAD_PATH}"
# In a real environment: aws s3 cp "\\${'$'}{TARBALL_PATH}" "\\${'$'}{UPLOAD_PATH}"
log_message "S3 upload simulated successfully."

# 7. Cleanup (only after successful "upload")
log_message "Cleaning up local snapshot and archive file..."
nodetool clearsnapshot -t "\\${'$'}{SNAPSHOT_TAG}"
rm -f "\\${'$'}{TARBALL_PATH}"

log_message "--- Full Cassandra Snapshot Backup Process Finished Successfully ---"

exit 0
`,
      'incremental-backup-to-s3.sh': `#!/bin/bash
# Archives and uploads existing incremental backup files to a simulated S3 bucket.

set -euo pipefail

# --- Configuration from JSON file ---
CONFIG_FILE="/etc/backup/config.json"

# --- Logging ---
# This function will be defined after LOG_FILE is sourced from config
log_message() {
  echo "[\\${'$'}(date +'%Y-%m-%d %H:%M:%S')] \\${'$'}1" | tee -a "\\${'$'}{LOG_FILE}"
}

# Check for config file and jq
if ! command -v jq &> /dev/null; then
  echo "[\\${'$'}(date +'%Y-%m-%d %H:%M:%S')] ERROR: jq is not installed. Please install jq to continue."
  exit 1
fi

if [ ! -f "\\${'$'}CONFIG_FILE" ]; then
  echo "[\\${'$'}(date +'%Y-%m-%d %H:%M:%S')] ERROR: Backup configuration file not found at \\${'$'}CONFIG_FILE"
  exit 1
fi

# Source configuration from JSON
S3_BUCKET_NAME=\\${'$'}(jq -r '.s3_bucket_name' "\\${'$'}CONFIG_FILE")
CASSANDRA_DATA_DIR=\\${'$'}(jq -r '.cassandra_data_dir' "\\${'$'}CONFIG_FILE")
LOG_FILE=\\${'$'}(jq -r '.incremental_backup_log_file' "\\${'$'}CONFIG_FILE")

# Validate sourced config
if [ -z "\\${'$'}S3_BUCKET_NAME" ] || [ -z "\\${'$'}CASSANDRA_DATA_DIR" ] || [ -z "\\${'$'}LOG_FILE" ]; then
  echo "[\\${'$'}(date +'%Y-%m-%d %H:%M:%S')] ERROR: One or more required configuration values are missing from \\${'$'}CONFIG_FILE"
  exit 1
fi


# --- Static Configuration ---
BACKUP_TAG="incremental_\\${'$'}(date +%Y%m%d%H%M%S)"
HOSTNAME=\\${'$'}(hostname -s)
BACKUP_ROOT_DIR="/tmp/cassandra_backups"
BACKUP_TEMP_DIR="\\${'$'}{BACKUP_ROOT_DIR}/\\${'$'}{HOSTNAME}_\\${'$'}{BACKUP_TAG}"
INCREMENTAL_MARKER="incremental_backup_contents.txt"

# --- Cleanup Functions ---
cleanup_temp_dir() {
  if [ -d "\\${'$'}{BACKUP_TEMP_DIR}" ]; then
    log_message "Cleaning up temporary directory: \\${'$'}{BACKUP_TEMP_DIR}"
    rm -rf "\\${'$'}{BACKUP_TEMP_DIR}"
  fi
}

# --- Main Logic ---
if [ "\\${'$'}(id -u)" -ne 0 ]; then
  log_message "ERROR: This script must be run as root."
  exit 1
fi

trap cleanup_temp_dir EXIT

log_message "--- Starting Incremental Cassandra Backup Process ---"
log_message "S3 Bucket: \\${'$'}{S3_BUCKET_NAME}"
log_message "Backup Tag: \\${'$'}{BACKUP_TAG}"

# 1. Create temporary directory structure
mkdir -p "\\${'$'}{BACKUP_TEMP_DIR}" || { log_message "ERROR: Failed to create temp backup directory."; exit 1; }

# 2. Collect incremental backup file paths
find "\\${'$'}{CASSANDRA_DATA_DIR}" -type f -path "*/backups/*" > "\\${'$'}{BACKUP_TEMP_DIR}/incremental_files.list"

# 3. Archive the files
if [ ! -s "\\${'$'}{BACKUP_TEMP_DIR}/incremental_files.list" ]; then
    log_message "No new incremental backup files found. Nothing to do."
    exit 0
fi

TARBALL_PATH="\\${'$'}{BACKUP_ROOT_DIR}/\\${'$'}{HOSTNAME}_\\${'$'}{BACKUP_TAG}.tar.gz"
log_message "Archiving incremental data to \\${'$'}{TARBALL_PATH}..."

tar -czf "\\${'$'}{TARBALL_PATH}" -P -T "\\${'$'}{BACKUP_TEMP_DIR}/incremental_files.list"
touch "\\${'$'}{BACKUP_TEMP_DIR}/\\${'$'}{INCREMENTAL_MARKER}"
tar -rf "\\${'$'}{TARBALL_PATH}" -C "\\${'$'}{BACKUP_TEMP_DIR}" "\\${'$'}{INCREMENTAL_MARKER}"

# 4. Upload to S3 (mocked)
UPLOAD_PATH="s3://\\${'$'}{S3_BUCKET_NAME}/cassandra/\\${'$'}{HOSTNAME}/incremental/\\${'$'}{BACKUP_TAG}.tar.gz"
log_message "Simulating S3 upload to: \\${'$'}{UPLOAD_PATH}"
# In a real environment: aws s3 cp "\\${'$'}{TARBALL_PATH}" "\\${'$'}{UPLOAD_PATH}"
log_message "S3 upload simulated successfully."

# 5. Cleanup (only after successful "upload")
log_message "Cleaning up archived incremental backup files and local tarball..."
xargs -a "\\${'$'}{BACKUP_TEMP_DIR}/incremental_files.list" rm -f
log_message "Source incremental files deleted."
rm -f "\\${'$'}{TARBALL_PATH}"
log_message "Local tarball deleted."

log_message "--- Incremental Cassandra Backup Process Finished Successfully ---"

exit 0
`,
      'prepare-replacement.sh': '#!/bin/bash\\necho "Prepare Replacement Script"',
      'version-check.sh': '#!/bin/bash\\necho "Version Check Script"',
      'cassandra_range_repair.py': '#!/usr/bin/env python3\\nprint("Cassandra Range Repair Python Script")',
      'range-repair.sh': '#!/bin/bash\\necho "Range Repair Script"',
      'robust_backup.sh': '#!/bin/bash\\necho "Robust Backup Script Placeholder"',
      'restore-from-s3.sh': `#!/bin/bash
# Restores a Cassandra node from a specified backup in S3.

set -euo pipefail

# --- Configuration & Input ---
BACKUP_ID="\\${'$'}1"
CONFIG_FILE="/etc/backup/config.json"
HOSTNAME=\\${'$'}(hostname -s)
RESTORE_LOG_FILE="/var/log/cassandra/restore.log"

# --- Logging ---
log_message() {
    echo "[\\${'$'}(date +'%Y-%m-%d %H:%M:%S')] \\${'$'}1" | tee -a "\\${'$'}{RESTORE_LOG_FILE}"
}

# --- Pre-flight Checks ---
if [ "\\${'$'}(id -u)" -ne 0 ]; then
    log_message "ERROR: This script must be run as root."
    exit 1
fi

if [ -z "\\${'$'}BACKUP_ID" ]; then
    log_message "ERROR: No backup ID provided."
    log_message "Usage: \\${'$'}0 <backup_id>"
    log_message "Example: \\${'$'}0 full_snapshot_20231027120000"
    exit 1
fi

if ! command -v jq &>/dev/null; then
    log_message "ERROR: jq is not installed. Please install jq to continue."
    exit 1
fi

if [ ! -f "\\${'$'}CONFIG_FILE" ]; then
    log_message "ERROR: Backup configuration file not found at \\${'$'}CONFIG_FILE"
    exit 1
fi

# --- Source configuration from JSON ---
S3_BUCKET_NAME=\\${'$'}(jq -r '.s3_bucket_name' "\\${'$'}CONFIG_FILE")
CASSANDRA_DATA_DIR=\\${'$'}(jq -r '.cassandra_data_dir' "\\${'$'}CONFIG_FILE")
CASSANDRA_COMMITLOG_DIR=\\${'$'}(jq -r '.commitlog_dir' "\\${'$'}CONFIG_FILE")
CASSANDRA_CACHES_DIR=\\${'$'}(jq -r '.saved_caches_dir' "\\${'$'}CONFIG_FILE")
CASSANDRA_USER="cassandra" # Usually static

log_message "--- Starting Cassandra Restore Process for Backup ID: \\${'$'}BACKUP_ID ---"

# Determine if it's a full or incremental backup to find the right S3 path
BACKUP_TYPE=\\${'$'}(echo "\\${'$'}BACKUP_ID" | cut -d'_' -f1)
TARBALL_NAME="\\${'$'}{HOSTNAME}_\\${'$'}{BACKUP_ID}.tar.gz"
S3_PATH="s3://\\${'$'}{S3_BUCKET_NAME}/cassandra/\\${'$'}{HOSTNAME}/\\${'$'}{BACKUP_TYPE}/\\${'$'}{TARBALL_NAME}"
LOCAL_TARBALL="/tmp/\\${'$'}{TARBALL_NAME}"

# --- Safety Confirmation ---
log_message "This is a DESTRUCTIVE operation. It will:"
log_message "1. STOP the Cassandra service."
log_message "2. DELETE all existing data, commitlogs, and caches."
log_message "3. DOWNLOAD and extract backup from \\${'$'}{S3_PATH}"
log_message "4. RESTART the Cassandra service."
read -p "Are you absolutely sure you want to continue? Type 'yes': " confirmation
if [[ "\\${'$'}confirmation" != "yes" ]]; then
    log_message "Restore aborted by user."
    exit 0
fi

# --- Execution ---
log_message "1. Stopping Cassandra service..."
systemctl stop cassandra

log_message "2. Cleaning old directories..."
rm -rf "\\${'$'}{CASSANDRA_DATA_DIR}"/*
rm -rf "\\${'$'}{CASSANDRA_COMMITLOG_DIR}"/*
rm -rf "\\${'$'}{CASSANDRA_CACHES_DIR}"/*
log_message "Old directories cleaned."

log_message "3. Downloading backup from \\${'$'}{S3_PATH}..."
# In a real environment, you would use: aws s3 cp "\\${'$'}{S3_PATH}" "\\${'$'}{LOCAL_TARBALL}"
# For this simulation, we'll create a dummy file.
touch "\\${'$'}{LOCAL_TARBALL}"
log_message "Simulated download of \\${'$'}{LOCAL_TARBALL} complete."

log_message "4. Extracting backup..."
# The -P flag is crucial here as the archive was created with absolute paths.
tar -xzf "\\${'$'}{LOCAL_TARBALL}" -P
log_message "Backup extracted."

log_message "5. Setting permissions..."
chown -R \\${'$'}{CASSANDRA_USER}:\\${'$'}{CASSANDRA_USER} "\\${'$'}{CASSANDRA_DATA_DIR}"
chown -R \\${'$'}{CASSANDRA_USER}:\\${'$'}{CASSANDRA_USER} "\\${'$'}{CASSANDRA_COMMITLOG_DIR}"
chown -R \\${'$'}{CASSANDRA_USER}:\\${'$'}{CASSANDRA_USER} "\\${'$'}{CASSANDRA_CACHES_DIR}"
log_message "Permissions set."

log_message "6. Starting Cassandra service..."
systemctl start cassandra
log_message "Service started. Waiting for it to initialize..."
sleep 60 # Give Cassandra time to start up

# 7. Refresh keyspaces if it was an incremental backup
if tar -tf "\\${'$'}{LOCAL_TARBALL}" | grep -q "incremental_backup_contents.txt"; then
    log_message "Incremental backup detected. Refreshing keyspaces..."
    # Get a list of non-system keyspaces
    KEYSPACES=\\${'$'}(cqlsh -e "DESCRIBE KEYSPACES;" | grep -vE "(system\\_auth|system\\_schema|system\\_traces|system\\_distributed|system)")
    for ks in \\${'$'}KEYSPACES; do
        log_message "Refreshing keyspace: \\${'$'}ks"
        nodetool refresh "\\${'$'}ks"
    done
    log_message "Keyspace refresh complete."
fi

# 8. Final cleanup
rm -f "\\${'$'}{LOCAL_TARBALL}"
log_message "--- Restore Process Finished Successfully ---"
exit 0
`,
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
usage: \\${'$'}0 [OPTIONS]

Checks the amount of disk space for '\\${'$'}{CASSANDRA_DATADIR}' against given thresholds.

Flags:
   -w INT   Sets the threshold which emits a warning (default: \\${'$'}WARNING_THRESHOLD)
   -c INT   Sets the threshold which is treated as CRITICAL (default: \\${'$'}CRITICAL_THRESHOLD)

   -r       When set, cassandra snapshots will be removed automagically if disk space is low.

Exit code of the script will be:

 0  - If free disk space is below critical and warning threshold.
 1  - If free disk space is below the warning threshold.
 2  - If free disk space is below the critical threshold.
EOF
}

function warning {
  local msg="\\${'$'}@"
  # shellcheck disable=SC2059
  printf "\\${'$'}{COL_LIGHT_MAGENTA}WARNING: \\${'$'}{msg}\\${'$'}{RESET}\\n" >&2
}

#
# Print an error message
#
# Usage in a script:
#   error "message"

function error {
  local msg="\\${'$'}@"
  # shellcheck disable=SC2059
  printf "\\${'$'}{BOLD}\\${'$'}{COL_RED}\\${'$'}{msg}\\${'$'}{RESET}\\n" >&2
}

function delete_snapshots {
  local cassandra_datadir="\\${'$'}1"

  find "\\${'$'}{cassandra_datadir}"/*/*/ -maxdepth 1 -mindepth 1 -type d -name snapshots | while read -r dir; do
    if [[ -n "\\${'$'}(find \\${'$'}{dir} -maxdepth 1 -mindepth 1 -type d -name "\\${'$'}{BACKUP_PREFIX}*" | head -n1)" ]]; then
      find "\\${'$'}{dir}" -maxdepth 1 -mindepth 1 -type d -name "\\${'$'}{BACKUP_PREFIX}*" -exec ls -t1d {} + | while read -r snapshot; do
        snapshot_name=\\${'$'}(basename "\\${'$'}snapshot")
        printf "\\e[35mINFO: Deleting snapshot %s for all keyspaces \\e[0m\\n" "\\${'$'}{snapshot_name}"
        nodetool clearsnapshot -t "\\${'$'}{snapshot_name}"
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
# disk_free=\\${'$'}(get_free_disk_space)
function get_free_disk_space {
  local mountpoint="\\${'$'}1"

  currently_used=\\${'$'}(df "\\${'$'}{mountpoint}" --output=pcent | tail -1 | tr -cd '[:digit:]')
  rc=\\${'$'}?
  if [[ -z "\\${'$'}currently_used" ]] || [[ \\${'$'}rc != 0 ]]; then
    error "Failed to get free disk space."
    exit 3
  fi

  echo \\${'$'}(( 100-currently_used ))

  return 0
}
#
# Check the disk space of a node
#
# Usage in a script:
#   if ! has_enough_free_disk_space NODENAME <MOUNTPOINT> <WARN_THRESHOLD> <CRITICAL_THRESHOLD>; then
#      warning "Disk space on \\${'$'}nodename is below threshold
#   fi

function has_enough_free_disk_space {
  local mountpoint="\\${'$'}1"
  if [ -z "\\${'$'}mountpoint" ]; then
    mountpoint="/"
  fi

  local warn_threshold="\\${'$'}2"
  if [ -z "\\${'$'}warn_threshold" ]; then
    warn_threshold="30"
  fi

  local crit_threshold="\\${'$'}3"
  if [ -z "\\${'$'}crit_threshold" ]; then
    crit_threshold="80"
  fi

  free_disk_space=\\${'$'}(get_free_disk_space "\\${'$'}mountpoint")

  if [[ \\${'$'}free_disk_space -lt \\${'$'}crit_threshold ]]; then
    error "Free disk space for '\\${'$'}mountpoint' is below \\${'$'}{crit_threshold} %%"
    return 2
  fi

  if [[ \\${'$'}free_disk_space -lt \\${'$'}warn_threshold ]]; then
    warning "Free disk space for '\\${'$'}mountpoint' is below \\${'$'}{warn_threshold}%%."
    return 1
  fi

  return 0
}

set -x
while getopts "hw:c:r" arg; do
  case \\${'$'}arg in
    h)
      usage
      ;;
    w)
      WARNING_THRESHOLD=\\${'$'}{OPTARG}
      ;;
    c)
      CRITICAL_THRESHOLD=\\${'$'}{OPTARG}
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
shift \\${'$'}((OPTIND-1))
set +x

MOUNTPOINT=\\${'$'}CASSANDRA_DATADIR

exit_code=2
if has_enough_free_disk_space "\\${'$'}MOUNTPOINT" "\\${'$'}WARNING_THRESHOLD" "\\${'$'}CRITICAL_THRESHOLD"; then
  disk_free=\\${'$'}(get_free_disk_space "\\${'$'}MOUNTPOINT")
  printf "Disk space is OK (free disk space: %d %% is above %d %%)\\n" "\\${'$'}disk_free" "\\${'$'}CRITICAL_THRESHOLD"
  exit_code=0
else
  if [[ \\${'$'}CLEAR_SNAPSHOTS == "true" ]]; then
    warning "Deleting snapshots to gain some free space."
    delete_snapshots "\\${'$'}MOUNTPOINT"
    sleep 10
    if has_enough_free_disk_space "\\${'$'}MOUNTPOINT" "\\${'$'}WARNING_THRESHOLD" "\\${'$'}CRITICAL_THRESHOLD"; then
      disk_free=\\${'$'}(get_free_disk_space "\\${'$'}MOUNTPOINT")
      printf "Disk space is now OK (free disk space: %d is below %d %%)\\n" "\\${'$'}disk_free" "\\${'$'}CRITICAL_THRESHOLD"
      exit_code=1
    fi
  fi
fi

exit "\\${'$'}exit_code"
`,
    };

