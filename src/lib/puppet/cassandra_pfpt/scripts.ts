
export const scripts = {
      'cassandra-upgrade-precheck.sh': '#!/bin/bash\\n# Placeholder for cassandra-upgrade-precheck.sh\\necho "Cassandra Upgrade Pre-check Script"',
      'cluster-health.sh': '#!/bin/bash\\nnodetool status',
      'repair-node.sh': '#!/bin/bash\\nnodetool repair -pr',
      'drain-node.sh': '#!/bin/bash\\nnodetool drain',
      'decommission-node.sh': `#!/bin/bash
# Securely decommissions a Cassandra node from the cluster.

log_message() {
  echo "[\\$(date +'%Y-%m-%d %H:%M:%S')] ${'$'}{1}"
}

log_message "INFO: This script will decommission the local Cassandra node."
log_message "This process will stream all of its data to other nodes in the cluster."
log_message "It cannot be undone."
log_message "Are you sure you want to proceed? Type 'yes' to confirm."

read -r confirmation

if [ "${'$'}{confirmation}" != "yes" ]; then
  log_message "Aborted. Node was not decommissioned."
  exit 0
fi

log_message "Starting nodetool decommission..."
nodetool decommission

DECOMMISSION_STATUS=${'$'}?

if [ ${'$'}{DECOMMISSION_STATUS} -eq 0 ]; then
  log_message "SUCCESS: Nodetool decommission completed successfully."
  log_message "It is now safe to shut down the cassandra service and turn off this machine."
  exit 0
else
  log_message "ERROR: Nodetool decommission FAILED with exit code ${'$'}{DECOMMISSION_STATUS}."
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
  echo "[\\$(date +'%Y-%m-%d %H:%M:%S')] ${'$'}{1}"
}

NODE_IP="${'$'}{1}"

if [ -z "${'$'}{NODE_IP}" ]; then
  log_message "Error: Node IP address must be provided as an argument."
  log_message "Usage: ${'$'}{0} <ip_address_of_dead_node>"
  exit 1
fi

log_message "WARNING: Attempting to assassinate node at IP: ${'$'}{NODE_IP}. This will remove it from the cluster."
log_message "Are you sure you want to proceed? Type 'yes' to confirm."
read confirmation

if [ "${'$'}{confirmation}" != "yes" ]; then
  log_message "Aborted."
  exit 0
fi

nodetool assassinate "${'$'}{NODE_IP}"
ASSASSINATE_STATUS=${'$'}?

if [ ${'$'}{ASSASSINATE_STATUS} -eq 0 ]; then
  log_message "Nodetool assassinate of ${'$'}{NODE_IP} completed successfully."
  exit 0
else
  log_message "Nodetool assassinate of ${'$'}{NODE_IP} FAILED with exit code ${'$'}{ASSASSINATE_STATUS}."
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
  echo "[\\$(date +'%Y-%m-%d %H:%M:%S')] ${'$'}{1}" | tee -a "${'$'}{LOG_FILE}"
}

# Check for config file and jq
if ! command -v jq &> /dev/null; then
  # Cannot use log_message here as LOG_FILE is not yet defined
  echo "[\\$(date +'%Y-%m-%d %H:%M:%S')] ERROR: jq is not installed. Please install jq to continue."
  exit 1
fi
if [ ! -f "${'$'}{CONFIG_FILE}" ]; then
  echo "[\\$(date +'%Y-%m-%d %H:%M:%S')] ERROR: Backup configuration file not found at ${'$'}{CONFIG_FILE}"
  exit 1
fi

# Source configuration from JSON
S3_BUCKET_NAME=\\$(jq -r '.s3_bucket_name' "${'$'}{CONFIG_FILE}")
CASSANDRA_DATA_DIR=\\$(jq -r '.cassandra_data_dir' "${'$'}{CONFIG_FILE}")
LOG_FILE=\\$(jq -r '.full_backup_log_file' "${'$'}{CONFIG_FILE}")
LISTEN_ADDRESS=\\$(jq -r '.listen_address' "${'$'}{CONFIG_FILE}")

# Validate sourced config
if [ -z "${'$'}{S3_BUCKET_NAME}" ] || [ -z "${'$'}{CASSANDRA_DATA_DIR}" ] || [ -z "${'$'}{LOG_FILE}" ]; then
  echo "[\\$(date +'%Y-%m-%d %H:%M:%S')] ERROR: One or more required configuration values are missing from ${'$'}{CONFIG_FILE}"
  exit 1
fi

# --- Static Configuration ---
SNAPSHOT_TAG="full_snapshot_\\$(date +%Y%m%d%H%M%S)"
HOSTNAME=\\$(hostname -s)
BACKUP_ROOT_DIR="/tmp/cassandra_backups"
BACKUP_TEMP_DIR="${'$'}{BACKUP_ROOT_DIR}/${'$'}{HOSTNAME}_${'$'}{SNAPSHOT_TAG}"


# --- Cleanup Functions ---
cleanup_temp_dir() {
  if [ -d "${'$'}{BACKUP_TEMP_DIR}" ]; then
    log_message "Cleaning up temporary directory: ${'$'}{BACKUP_TEMP_DIR}"
    rm -rf "${'$'}{BACKUP_TEMP_DIR}"
  fi
}

# --- Main Logic ---
if [ "\\$(id -u)" -ne 0 ]; then
  log_message "ERROR: This script must be run as root."
  exit 1
fi

trap cleanup_temp_dir EXIT

log_message "--- Starting Full Cassandra Snapshot Backup Process ---"
log_message "S3 Bucket: ${'$'}{S3_BUCKET_NAME}"
log_message "Snapshot Tag: ${'$'}{SNAPSHOT_TAG}"

# 1. Create temporary directory structure
mkdir -p "${'$'}{BACKUP_TEMP_DIR}" || { log_message "ERROR: Failed to create temp backup directories."; exit 1; }

# 2. Create Backup Manifest
MANIFEST_FILE="${'$'}{BACKUP_TEMP_DIR}/backup_manifest.json"
log_message "Creating backup manifest at ${'$'}{MANIFEST_FILE}..."

CLUSTER_NAME=\\$(nodetool describecluster | grep 'Name:' | awk '{print \\$2}')

if [ -n "${'$'}{LISTEN_ADDRESS}" ]; then
    NODE_IP="${'$'}{LISTEN_ADDRESS}"
else
    NODE_IP="\\$(hostname -i)"
fi

NODE_STATUS_LINE=\\$(nodetool status | grep "\\b${'$'}{NODE_IP}\\b")
NODE_DC=\\$(echo "${'$'}{NODE_STATUS_LINE}" | awk '{print \\$5}')
NODE_RACK=\\$(echo "${'$'}{NODE_STATUS_LINE}" | awk '{print \\$6}')
NODE_TOKENS=\\$(nodetool ring | grep "\\b${'$'}{NODE_IP}\\b" | awk '{print \\$NF}' | tr '\\n' ',' | sed 's/,$//')

jq -n \\
  --arg cluster_name "${'$'}{CLUSTER_NAME}" \\
  --arg backup_id "${'$'}{SNAPSHOT_TAG}" \\
  --arg backup_type "full" \\
  --arg timestamp "\\$(date --iso-8601=seconds)" \\
  --arg node_ip "${'$'}{NODE_IP}" \\
  --arg node_dc "${'$'}{NODE_DC}" \\
  --arg node_rack "${'$'}{NODE_RACK}" \\
  --arg tokens "${'$'}{NODE_TOKENS}" \\
  '{
    "cluster_name": ${'$'}cluster_name,
    "backup_id": ${'$'}backup_id,
    "backup_type": ${'$'}backup_type,
    "timestamp_utc": ${'$'}timestamp,
    "source_node": {
      "ip_address": ${'$'}node_ip,
      "datacenter": ${'$'}node_dc,
      "rack": ${'$'}node_rack,
      "tokens": (${'$'}tokens | split(","))
    }
  }' > "${'$'}{MANIFEST_FILE}"

log_message "Manifest created successfully."


# 3. Take a node-local snapshot
log_message "Taking full snapshot with tag: ${'$'}{SNAPSHOT_TAG}..."
if ! nodetool snapshot -t "${'$'}{SNAPSHOT_TAG}"; then
  log_message "ERROR: Failed to take Cassandra snapshot. Aborting backup."
  exit 1
fi
log_message "Full snapshot taken successfully."

# 4. Collect snapshot file paths
find "${'$'}{CASSANDRA_DATA_DIR}" -type f -path "*/snapshots/${'$'}{SNAPSHOT_TAG}/*" > "${'$'}{BACKUP_TEMP_DIR}/snapshot_files.list"

# 5. Archive the files
TARBALL_PATH="${'$'}{BACKUP_ROOT_DIR}/${'$'}{HOSTNAME}_${'$'}{SNAPSHOT_TAG}.tar.gz"
log_message "Archiving snapshot data to ${'$'}{TARBALL_PATH}..."

if [ ! -s "${'$'}{BACKUP_TEMP_DIR}/snapshot_files.list" ]; then
    log_message "WARNING: No snapshot files found. The cluster may be empty. Aborting backup."
    nodetool clearsnapshot -t "${'$'}{SNAPSHOT_TAG}"
    exit 0
fi

tar -czf "${'$'}{TARBALL_PATH}" -P -T "${'$'}{BACKUP_TEMP_DIR}/snapshot_files.list"
tar -rf "${'$'}{TARBALL_PATH}" -C "${'$'}{BACKUP_TEMP_DIR}" "backup_manifest.json"
log_message "Backup manifest appended to archive."

# 6. Archive the schema
log_message "Backing up schema..."
SCHEMA_FILE="${'$'}{BACKUP_TEMP_DIR}/schema.cql"
timeout 30 cqlsh -e "DESCRIBE SCHEMA;" > "${'$'}{SCHEMA_FILE}"
if [ ${'$'}? -ne 0 ]; then
  log_message "WARNING: Failed to dump schema. Backup will continue without it."
else
  # Add schema to the existing tarball
  tar -rf "${'$'}{TARBALL_PATH}" -C "${'$'}{BACKUP_TEMP_DIR}" "schema.cql"
  log_message "Schema appended to archive."
fi

# 7. Upload to S3 (mocked)
UPLOAD_PATH="s3://${'$'}{S3_BUCKET_NAME}/cassandra/${'$'}{HOSTNAME}/full/${'$'}{SNAPSHOT_TAG}.tar.gz"
log_message "Simulating S3 upload to: ${'$'}{UPLOAD_PATH}"
# In a real environment: aws s3 cp "${'$'}{TARBALL_PATH}" "${'$'}{UPLOAD_PATH}"
log_message "S3 upload simulated successfully."

# 8. Cleanup (only after successful "upload")
log_message "Cleaning up local snapshot and archive file..."
nodetool clearsnapshot -t "${'$'}{SNAPSHOT_TAG}"
rm -f "${'$'}{TARBALL_PATH}"

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
  echo "[\\$(date +'%Y-%m-%d %H:%M:%S')] ${'$'}{1}" | tee -a "${'$'}{LOG_FILE}"
}

# Check for config file and jq
if ! command -v jq &> /dev/null; then
  echo "[\\$(date +'%Y-%m-%d %H:%M:%S')] ERROR: jq is not installed. Please install jq to continue."
  exit 1
fi

if [ ! -f "${'$'}{CONFIG_FILE}" ]; then
  echo "[\\$(date +'%Y-%m-%d %H:%M:%S')] ERROR: Backup configuration file not found at ${'$'}{CONFIG_FILE}"
  exit 1
fi

# Source configuration from JSON
S3_BUCKET_NAME=\\$(jq -r '.s3_bucket_name' "${'$'}{CONFIG_FILE}")
CASSANDRA_DATA_DIR=\\$(jq -r '.cassandra_data_dir' "${'$'}{CONFIG_FILE}")
LOG_FILE=\\$(jq -r '.incremental_backup_log_file' "${'$'}{CONFIG_FILE}")
LISTEN_ADDRESS=\\$(jq -r '.listen_address' "${'$'}{CONFIG_FILE}")


# Validate sourced config
if [ -z "${'$'}{S3_BUCKET_NAME}" ] || [ -z "${'$'}{CASSANDRA_DATA_DIR}" ] || [ -z "${'$'}{LOG_FILE}" ]; then
  echo "[\\$(date +'%Y-%m-%d %H:%M:%S')] ERROR: One or more required configuration values are missing from ${'$'}{CONFIG_FILE}"
  exit 1
fi


# --- Static Configuration ---
BACKUP_TAG="incremental_\\$(date +%Y%m%d%H%M%S)"
HOSTNAME=\\$(hostname -s)
BACKUP_ROOT_DIR="/tmp/cassandra_backups"
BACKUP_TEMP_DIR="${'$'}{BACKUP_ROOT_DIR}/${'$'}{HOSTNAME}_${'$'}{BACKUP_TAG}"

# --- Cleanup Functions ---
cleanup_temp_dir() {
  if [ -d "${'$'}{BACKUP_TEMP_DIR}" ]; then
    log_message "Cleaning up temporary directory: ${'$'}{BACKUP_TEMP_DIR}"
    rm -rf "${'$'}{BACKUP_TEMP_DIR}"
  fi
}

# --- Main Logic ---
if [ "\\$(id -u)" -ne 0 ]; then
  log_message "ERROR: This script must be run as root."
  exit 1
fi

trap cleanup_temp_dir EXIT

log_message "--- Starting Incremental Cassandra Backup Process ---"
log_message "S3 Bucket: ${'$'}{S3_BUCKET_NAME}"
log_message "Backup Tag: ${'$'}{BACKUP_TAG}"

# 1. Create temporary directory structure
mkdir -p "${'$'}{BACKUP_TEMP_DIR}" || { log_message "ERROR: Failed to create temp backup directory."; exit 1; }


# 2. Collect incremental backup file paths
find "${'$'}{CASSANDRA_DATA_DIR}" -type f -path "*/backups/*" > "${'$'}{BACKUP_TEMP_DIR}/incremental_files.list"

# 3. Check if there are files to back up
if [ ! -s "${'$'}{BACKUP_TEMP_DIR}/incremental_files.list" ]; then
    log_message "No new incremental backup files found. Nothing to do."
    exit 0
fi

# 4. Create Backup Manifest
MANIFEST_FILE="${'$'}{BACKUP_TEMP_DIR}/backup_manifest.json"
log_message "Creating backup manifest at ${'$'}{MANIFEST_FILE}..."

CLUSTER_NAME=\\$(nodetool describecluster | grep 'Name:' | awk '{print \\$2}')

if [ -n "${'$'}{LISTEN_ADDRESS}" ]; then
    NODE_IP="${'$'}{LISTEN_ADDRESS}"
else
    NODE_IP="\\$(hostname -i)"
fi

NODE_STATUS_LINE=\\$(nodetool status | grep "\\b${'$'}{NODE_IP}\\b")
NODE_DC=\\$(echo "${'$'}{NODE_STATUS_LINE}" | awk '{print \\$5}')
NODE_RACK=\\$(echo "${'$'}{NODE_STATUS_LINE}" | awk '{print \\$6}')
NODE_TOKENS=\\$(nodetool ring | grep "\\b${'$'}{NODE_IP}\\b" | awk '{print \\$NF}' | tr '\\n' ',' | sed 's/,$//')

jq -n \\
  --arg cluster_name "${'$'}{CLUSTER_NAME}" \\
  --arg backup_id "${'$'}{BACKUP_TAG}" \\
  --arg backup_type "incremental" \\
  --arg timestamp "\\$(date --iso-8601=seconds)" \\
  --arg node_ip "${'$'}{NODE_IP}" \\
  --arg node_dc "${'$'}{NODE_DC}" \\
  --arg node_rack "${'$'}{NODE_RACK}" \\
  --arg tokens "${'$'}{NODE_TOKENS}" \\
  '{
    "cluster_name": ${'$'}cluster_name,
    "backup_id": ${'$'}backup_id,
    "backup_type": ${'$'}backup_type,
    "timestamp_utc": ${'$'}timestamp,
    "source_node": {
      "ip_address": ${'$'}node_ip,
      "datacenter": ${'$'}node_dc,
      "rack": ${'$'}node_rack,
      "tokens": (${'$'}tokens | split(","))
    }
  }' > "${'$'}{MANIFEST_FILE}"

log_message "Manifest created successfully."


# 5. Archive the files
TARBALL_PATH="${'$'}{BACKUP_ROOT_DIR}/${'$'}{HOSTNAME}_${'$'}{BACKUP_TAG}.tar.gz"
log_message "Archiving incremental data to ${'$'}{TARBALL_PATH}..."

tar -czf "${'$'}{TARBALL_PATH}" -P -T "${'$'}{BACKUP_TEMP_DIR}/incremental_files.list"
tar -rf "${'$'}{TARBALL_PATH}" -C "${'$'}{BACKUP_TEMP_DIR}" "backup_manifest.json"
log_message "Backup manifest appended to archive."

# 6. Upload to S3 (mocked)
UPLOAD_PATH="s3://${'$'}{S3_BUCKET_NAME}/cassandra/${'$'}{HOSTNAME}/incremental/${'$'}{BACKUP_TAG}.tar.gz"
log_message "Simulating S3 upload to: ${'$'}{UPLOAD_PATH}"
# In a real environment: aws s3 cp "${'$'}{TARBALL_PATH}" "${'$'}{UPLOAD_PATH}"
log_message "S3 upload simulated successfully."

# 7. Cleanup (only after successful "upload")
log_message "Cleaning up archived incremental backup files and local tarball..."
xargs -a "${'$'}{BACKUP_TEMP_DIR}/incremental_files.list" rm -f
log_message "Source incremental files deleted."
rm -f "${'$'}{TARBALL_PATH}"
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
# Supports full node restore, granular keyspace/table restore, and schema-only extraction.

set -euo pipefail

# --- Configuration & Input ---
CONFIG_FILE="/etc/backup/config.json"
HOSTNAME=\\$(hostname -s)
RESTORE_LOG_FILE="/var/log/cassandra/restore.log"
BACKUP_ID=""
KEYSPACE_NAME=""
TABLE_NAME=""

# --- Logging ---
log_message() {
    echo "[\\$(date +'%Y-%m-%d %H:%M:%S')] ${'$'}{1}" | tee -a "${'$'}{RESTORE_LOG_FILE}"
}

# --- Usage ---
usage() {
    log_message "Usage: ${'$'}{0} [mode] [backup_id] [keyspace] [table]"
    log_message "Modes:"
    log_message "  Full Restore (destructive): ${'$'}{0} <backup_id>"
    log_message "  Granular Restore:           ${'$'}{0} <backup_id> <keyspace_name> [table_name]"
    log_message "  Schema-Only Restore:        ${'$'}{0} --schema-only <backup_id>"
    exit 1
}


# --- Pre-flight Checks ---
if [ "\\$(id -u)" -ne 0 ]; then
    log_message "ERROR: This script must be run as root."
    exit 1
fi

for tool in jq aws sstableloader; do
    if ! command -v ${'$'}{tool} &>/dev/null; then
        log_message "ERROR: Required tool '${'$'}{tool}' is not installed or not in PATH."
        exit 1
    fi
done

if [ ! -f "${'$'}{CONFIG_FILE}" ]; then
    log_message "ERROR: Backup configuration file not found at ${'$'}{CONFIG_FILE}"
    exit 1
fi

# --- Source configuration from JSON ---
S3_BUCKET_NAME=\\$(jq -r '.s3_bucket_name' "${'$'}{CONFIG_FILE}")
CASSANDRA_DATA_DIR=\\$(jq -r '.cassandra_data_dir' "${'$'}{CONFIG_FILE}")
CASSANDRA_COMMITLOG_DIR=\\$(jq -r '.commitlog_dir' "${'$'}{CONFIG_FILE}")
CASSANDRA_CACHES_DIR=\\$(jq -r '.saved_caches_dir' "${'$'}{CONFIG_FILE}")
LISTEN_ADDRESS=\\$(jq -r '.listen_address' "${'$'}{CONFIG_FILE}")
SEEDS=\\$(jq -r '.seeds_list | join(",")' "${'$'}{CONFIG_FILE}")
CASSANDRA_USER="cassandra" # Usually static

# Determine node list for sstableloader. Use seeds if available, otherwise localhost.
if [ -n "${'$'}{SEEDS}" ]; then
    LOADER_NODES="${'$'}{SEEDS}"
else
    LOADER_NODES="${'$'}{LISTEN_ADDRESS}"
fi


# --- Function for Schema-Only Restore ---
do_schema_restore() {
    local MANIFEST_JSON="${'$'}1"
    log_message "--- Starting Schema-Only Restore for Backup ID: ${'$'}{BACKUP_ID} ---"

    log_message "Downloading backup to extract schema..."
    if aws s3 cp "${'$'}{S3_PATH}" - | tar -xzf - --to-stdout schema.cql > /tmp/schema.cql 2>/dev/null; then
        log_message "SUCCESS: Schema extracted to /tmp/schema.cql"
        log_message "Please review this file, then apply it to your cluster using: cqlsh -u <user> -p <password> -f /tmp/schema.cql"
    else
        log_message "ERROR: Failed to extract schema.cql from the backup. The backup may be corrupted or may not contain a schema file."
        exit 1
    fi
    log_message "--- Schema-Only Restore Finished ---"
}


# --- Function for Full Node Restore ---
do_full_restore() {
    local MANIFEST_JSON="${'$'}1"
    log_message "--- Starting FULL DESTRUCTIVE Node Restore for Backup ID: ${'$'}{BACKUP_ID} ---"

    log_message "This is a DESTRUCTIVE operation. It will:"
    log_message "1. STOP the Cassandra service."
    log_message "2. DELETE all existing data, commitlogs, and caches."
    log_message "3. DOWNLOAD and extract backup from S3."
    log_message "4. CONFIGURE node replacement if needed (for DR)."
    log_message "5. RESTART the Cassandra service."
    read -p "Are you absolutely sure you want to continue with a full restore? Type 'yes': " confirmation
    if [[ "${'$'}{confirmation}" != "yes" ]]; then
        log_message "Restore aborted by user."
        exit 0
    fi

    log_message "1. Stopping Cassandra service..."
    systemctl stop cassandra

    log_message "2. Cleaning old directories..."
    rm -rf "${'$'}{CASSANDRA_DATA_DIR}"/*
    rm -rf "${'$'}{CASSANDRA_COMMITLOG_DIR}"/*
    rm -rf "${'$'}{CASSANDRA_CACHES_DIR}"/*
    log_message "Old directories cleaned."
    
    local ORIGINAL_IP=\\$(echo "${'$'}{MANIFEST_JSON}" | jq -r '.source_node.ip_address')
    if [ -z "${'$'}{ORIGINAL_IP}" ]; then
        log_message "ERROR: Could not parse original node IP from backup manifest. Aborting."
        exit 1
    fi
    log_message "Original node IP from manifest: ${'$'}{ORIGINAL_IP}"

    log_message "3. Downloading and extracting backup..."
    if ! aws s3 cp "${'$'}{S3_PATH}" - | tar -xzf - -P; then
        log_message "ERROR: Failed to download or extract backup from S3."
        exit 1
    fi
    log_message "Backup extracted."
    
    local JVM_OPTIONS_FILE="/etc/cassandra/conf/jvm-server.options"

    # CRITICAL STEP: Configure node replacement if this is a DR scenario
    if [ "${'$'}{ORIGINAL_IP}" != "${'$'}{LISTEN_ADDRESS}" ]; then
        log_message "DR SCENARIO DETECTED: This backup is from a different node (${'$'}{ORIGINAL_IP})."
        log_message "Configuring this node to replace it by setting 'cassandra.replace_address_first_boot'."

        # Clean up any previous replacement flags first for idempotency
        sed -i '/cassandra.replace_address_first_boot/d' "${'$'}{JVM_OPTIONS_FILE}"

        # Add the new flag
        echo "-Dcassandra.replace_address_first_boot=${'$'}{ORIGINAL_IP}" >> "${'$'}{JVM_OPTIONS_FILE}"
    else
        log_message "INFO: Restoring backup to the original node (${'$'}{LISTEN_ADDRESS}). No node replacement is necessary."
    fi

    log_message "4. Setting permissions..."
    chown -R ${'$'}{CASSANDRA_USER}:${'$'}{CASSANDRA_USER} "${'$'}{CASSANDRA_DATA_DIR}"
    chown -R ${'$'}{CASSANDRA_USER}:${'$'}{CASSANDRA_USER} "${'$'}{CASSANDRA_COMMITLOG_DIR}"
    chown -R ${'$'}{CASSANDRA_USER}:${'$'}{CASSANDRA_USER} "${'$'}{CASSANDRA_CACHES_DIR}"
    log_message "Permissions set."

    log_message "5. Starting Cassandra service..."
    systemctl start cassandra
    log_message "Service started. Waiting for node to initialize..."

    # Wait for the node to come up before cleaning up the flag
    local CASSANDRA_READY=false
    for i in {1..30}; do # Wait up to 5 minutes (30 * 10 seconds)
        if nodetool status > /dev/null 2>&1; then
            CASSANDRA_READY=true
            break
        fi
        log_message "Waiting for Cassandra to be ready... (attempt ${'$'}i of 30)"
        sleep 10
    done

    if [ "${'$'}{CASSANDRA_READY}" = true ]; then
        log_message "SUCCESS: Cassandra node is up and running."
        # Clean up the replacement flag so it doesn't get used on the next restart
        if [ "${'$'}{ORIGINAL_IP}" != "${'$'}{LISTEN_ADDRESS}" ]; then
            log_message "Cleaning up replace_address_first_boot flag."
            sed -i '/cassandra.replace_address_first_boot/d' "${'$'}{JVM_OPTIONS_FILE}"
        fi
    else
        log_message "ERROR: Cassandra node failed to start within 5 minutes. Please check system logs for errors."
        exit 1
    fi
    
    log_message "--- Full Restore Process Finished Successfully ---"
}

# --- Function for Granular Restore using sstableloader ---
do_granular_restore() {
    local MANIFEST_JSON="${'$'}1"
    local restore_path
    local restore_type

    if [ -n "${'$'}{TABLE_NAME}" ]; then
        restore_type="Table '${'$'}{TABLE_NAME}' in Keyspace '${'$'}{KEYSPACE_NAME}'"
    else
        restore_type="Keyspace '${'$'}{KEYSPACE_NAME}'"
    fi

    log_message "--- Starting GRANULAR Restore for ${'$'}{restore_type} from Backup ID: ${'$'}{BACKUP_ID} ---"
    log_message "This will stream data into the LIVE cluster using sstableloader."

    local RESTORE_TEMP_DIR="/tmp/restore_${'$'}{BACKUP_ID}_${'$'}{KEYSPACE_NAME}"
    trap 'rm -rf "${'$'}{RESTORE_TEMP_DIR}"' EXIT
    mkdir -p "${'$'}{RESTORE_TEMP_DIR}"

    log_message "Downloading and extracting backup to temporary directory..."
    aws s3 cp "${'$'}{S3_PATH}" - | tar -xzf - -C "${'$'}{RESTORE_TEMP_DIR}"
    
    # sstableloader needs the path to be .../keyspace/table/
    # The backup preserves the full path, so we can find it.
    local extracted_data_path="${'$'}{RESTORE_TEMP_DIR}${'$'}{CASSANDRA_DATA_DIR}"

    if [ -n "${'$'}{TABLE_NAME}" ]; then
        # Find the specific table directory (it has a UUID suffix)
        restore_path=\\$(find "${'$'}{extracted_data_path}/${'$'}{KEYSPACE_NAME}" -maxdepth 1 -type d -name "${'$'}{TABLE_NAME}-*")
        if [ -z "${'$'}restore_path" ] || [ ! -d "${'$'}restore_path" ]; then
            log_message "ERROR: Could not find table '${'$'}{TABLE_NAME}' in the backup for keyspace '${'$'}{KEYSPACE_NAME}'."
            exit 1
        fi
    else
        restore_path="${'$'}{extracted_data_path}/${'$'}{KEYSPACE_NAME}"
        if [ ! -d "${'$'}restore_path" ]; then
            log_message "ERROR: Could not find keyspace '${'$'}{KEYSPACE_NAME}' in the backup."
            exit 1
        fi
    fi

    log_message "Found data to restore at: ${'$'}restore_path"
    log_message "Streaming data to cluster nodes (${'$'}{LOADER_NODES}) with sstableloader..."

    # Ensure the schema exists before loading data
    log_message "Verifying schema exists..."
    if ! cqlsh -e "DESCRIBE KEYSPACE ${'$'}{KEYSPACE_NAME};" &>/dev/null; then
        log_message "ERROR: Keyspace '${'$'}{KEYSPACE_NAME}' does not exist in the cluster."
        log_message "You must restore the schema before you can load data."
        log_message "Use the --schema-only flag to extract the schema from your backup:"
        log_message "  ${'$'}{0} --schema-only <backup_id>"
        log_message "Then apply it using: cqlsh -f /tmp/schema.cql"
        exit 1
    fi

    # Run the loader
    if sstableloader -d "${'$'}{LOADER_NODES}" "${'$'}{restore_path}"; then
        log_message "sstableloader completed successfully."
    else
        log_message "ERROR: sstableloader failed. Check its output above for details."
        exit 1
    fi

    log_message "Cleaning up temporary files..."
    rm -rf "${'$'}{RESTORE_TEMP_DIR}"
    trap - EXIT

    log_message "--- Granular Restore Process Finished Successfully ---"
}


# --- Main Logic: Argument Parsing ---

if [ "${'$'}#" -eq 0 ]; then
    usage
fi

if [ "${'$'}{1}" == "--schema-only" ]; then
    if [ -z "${'$'}{2}" ]; then
      log_message "ERROR: Backup ID must be provided after --schema-only flag."
      usage
    fi
    BACKUP_ID="${'$'}{2}"
    MODE="schema"
else
    BACKUP_ID="${'$'}{1}"
    KEYSPACE_NAME="${'$'}{2}"
    TABLE_NAME="${'$'}{3}"
    if [ -z "${'$'}{BACKUP_ID}" ]; then
        usage
    elif [ -z "${'$'}{KEYSPACE_NAME}" ]; then
        MODE="full"
    else
        MODE="granular"
    fi
fi


# --- Main Logic: Execution ---

# Determine backup type to find the right S3 path
BACKUP_TYPE=\\$(echo "${'$'}{BACKUP_ID}" | cut -d'_' -f1)
if [[ "${'$'}{BACKUP_TYPE}" != "full" && "${'$'}{BACKUP_TYPE}" != "incremental" ]]; then
    log_message "ERROR: Backup ID must start with 'full_' or 'incremental_'. Invalid ID: ${'$'}{BACKUP_ID}"
    exit 1
fi

TARBALL_NAME="${'$'}{HOSTNAME}_${'$'}{BACKUP_ID}.tar.gz"
S3_PATH="s3://${'$'}{S3_BUCKET_NAME}/cassandra/${'$'}{HOSTNAME}/${'$'}{BACKUP_TYPE}/${'$'}{TARBALL_NAME}"

log_message "Preparing to restore from S3 path: ${'$'}{S3_PATH}"

# --- Fetch and verify manifest first ---
log_message "Fetching backup manifest for verification..."
MANIFEST_JSON=\\$(aws s3 cp "${'$'}{S3_PATH}" - | tar -xzf - --to-stdout backup_manifest.json 2>/dev/null)

if [ -z "${'$'}{MANIFEST_JSON}" ]; then
    log_message "ERROR: Failed to fetch or find backup_manifest.json in the archive. The backup may be invalid or the S3 path incorrect."
    exit 1
fi

log_message "----------------- BACKUP MANIFEST -----------------"
echo "${'$'}{MANIFEST_JSON}" | jq '.' | tee -a "${'$'}{RESTORE_LOG_FILE}"
log_message "---------------------------------------------------"
read -p "Does the manifest above look correct? Type 'yes' to proceed: " manifest_confirmation
if [[ "${'$'}{manifest_confirmation}" != "yes" ]]; then
    log_message "Restore aborted by user based on manifest review."
    exit 0
fi

# --- Now, execute the chosen mode ---
case ${'$'}MODE in
    "schema")
        do_schema_restore "${'$'}{MANIFEST_JSON}"
        ;;
    "full")
        do_full_restore "${'$'}{MANIFEST_JSON}"
        ;;
    "granular")
        do_granular_restore "${'$'}{MANIFEST_JSON}"
        ;;
    *)
        log_message "INTERNAL ERROR: Invalid mode detected."
        exit 1
        ;;
esac

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
usage: ${'$'}{0} [OPTIONS]

Checks the amount of disk space for '${'$'}{CASSANDRA_DATADIR}' against given thresholds.

Flags:
   -w INT   Sets the threshold which emits a warning (default: ${'$'}WARNING_THRESHOLD)
   -c INT   Sets the threshold which is treated as CRITICAL (default: ${'$'}CRITICAL_THRESHOLD)

   -r       When set, cassandra snapshots will be removed automagically if disk space is low.

Exit code of the script will be:

 0  - If free disk space is below critical and warning threshold.
 1  - If free disk space is below the warning threshold.
 2  - If free disk space is below the critical threshold.
EOF
}

function warning {
  local msg="${'$'}@"
  # shellcheck disable=SC2059
  printf "${'$'}{COL_LIGHT_MAGENTA}WARNING: ${'$'}{msg}${'$'}{RESET}\\n" >&2
}

#
# Print an error message
#
# Usage in a script:
#   error "message"

function error {
  local msg="${'$'}@"
  # shellcheck disable=SC2059
  printf "${'$'}{BOLD}${'$'}{COL_RED}${'$'}{msg}${'$'}{RESET}\\n" >&2
}

function delete_snapshots {
  local cassandra_datadir="${'$'}{1}"

  find "${'$'}{cassandra_datadir}"/*/*/ -maxdepth 1 -mindepth 1 -type d -name snapshots | while read -r dir; do
    if [[ -n "\\$(find ${'$'}{dir} -maxdepth 1 -mindepth 1 -type d -name "${'$'}{BACKUP_PREFIX}*" | head -n1)" ]]; then
      find "${'$'}{dir}" -maxdepth 1 -mindepth 1 -type d -name "${'$'}{BACKUP_PREFIX}*" -exec ls -t1d {} + | while read -r snapshot; do
        snapshot_name=\\$(basename "${'$'}snapshot")
        printf "\\e[35mINFO: Deleting snapshot %s for all keyspaces \\e[0m\\n" "${'$'}{snapshot_name}"
        nodetool clearsnapshot -t "${'$'}{snapshot_name}"
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
# disk_free=\\$(get_free_disk_space)
function get_free_disk_space {
  local mountpoint="${'$'}{1}"

  currently_used=\\$(df "${'$'}{mountpoint}" --output=pcent | tail -1 | tr -cd '[:digit:]')
  rc=${'$'}?
  if [[ -z "${'$'}currently_used" ]] || [[ ${'$'}rc != 0 ]]; then
    error "Failed to get free disk space."
    exit 3
  fi

  echo \\$(( 100-currently_used ))

  return 0
}
#
# Check the disk space of a node
#
# Usage in a script:
#   if ! has_enough_free_disk_space NODENAME <MOUNTPOINT> <WARN_THRESHOLD> <CRITICAL_THRESHOLD>; then
#      warning "Disk space on ${'$'}nodename is below threshold
#   fi

function has_enough_free_disk_space {
  local mountpoint
  if [ -n "${'$'}{1}" ]; then
    mountpoint="${'$'}{1}"
  else
    mountpoint="/"
  fi

  local warn_threshold
  if [ -n "${'$'}{2}" ]; then
    warn_threshold="${'$'}{2}"
  else
    warn_threshold="30"
  fi

  local crit_threshold
  if [ -n "${'$'}{3}" ]; then
    crit_threshold="${'$'}{3}"
  else
    crit_threshold="80"
  fi

  free_disk_space=\\$(get_free_disk_space "${'$'}mountpoint")

  if [[ ${'$'}free_disk_space -lt ${'$'}crit_threshold ]]; then
    error "Free disk space for '${'$'}mountpoint' is below ${'$'}{crit_threshold} %%"
    return 2
  fi

  if [[ ${'$'}free_disk_space -lt ${'$'}warn_threshold ]]; then
    warning "Free disk space for '${'$'}mountpoint' is below ${'$'}{warn_threshold}%%."
    return 1
  fi

  return 0
}

set -x
while getopts "hw:c:r" arg; do
  case ${'$'}arg in
    h)
      usage
      ;;
    w)
      WARNING_THRESHOLD=${'$'}{OPTARG}
      ;;
    c)
      CRITICAL_THRESHOLD=${'$'}{OPTARG}
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
shift \\$((OPTIND-1))
set +x

MOUNTPOINT=${'$'}CASSANDRA_DATADIR

exit_code=2
if has_enough_free_disk_space "${'$'}MOUNTPOINT" "${'$'}WARNING_THRESHOLD" "${'$'}CRITICAL_THRESHOLD"; then
  disk_free=\\$(get_free_disk_space "${'$'}MOUNTPOINT")
  printf "Disk space is OK (free disk space: %d %% is above %d %%)\\n" "${'$'}disk_free" "${'$'}CRITICAL_THRESHOLD"
  exit_code=0
else
  if [[ ${'$'}CLEAR_SNAPSHOTS == "true" ]]; then
    warning "Deleting snapshots to gain some free space."
    delete_snapshots "${'$'}MOUNTPOINT"
    sleep 10
    if has_enough_free_disk_space "${'$'}MOUNTPOINT" "${'$'}WARNING_THRESHOLD" "${'$'}CRITICAL_THRESHOLD"; then
      disk_free=\\$(get_free_disk_space "${'$'}MOUNTPOINT")
      printf "Disk space is now OK (free disk space: %d is below %d %%)\\n" "${'$'}disk_free" "${'$'}CRITICAL_THRESHOLD"
      exit_code=1
    fi
  fi
fi

exit "${'$'}exit_code"
`,
    };

