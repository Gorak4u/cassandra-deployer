#!/bin/bash
# This file is managed by Puppet.
# Verifies the integrity of the latest backup set for this node.

set -euo pipefail

# This script needs to run with /bin/bash to support PIPESTATUS
if [ -z "$BASH_VERSION" ]; then
    exec /bin/bash "$0" "$@"
fi

# --- Color Codes ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# --- Configuration & Logging Initialization ---
CONFIG_FILE="/etc/backup/config.json"
LOG_FILE="/var/log/cassandra/backup_verify.log"

log_message() {
  echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}
log_info() { log_message "${BLUE}$1${NC}"; }
log_success() { log_message "${GREEN}$1${NC}"; }
log_warn() { log_message "${YELLOW}$1${NC}"; }
log_error() { log_message "${RED}$1${NC}"; }


# --- Pre-flight Checks ---
for tool in jq aws openssl tar; do
    if ! command -v $tool &> /dev/null; then log_error "Required tool '$tool' is not installed or in PATH."; exit 1; fi
done
if [ ! -f "$CONFIG_FILE" ]; then log_error "Backup configuration file not found at $CONFIG_FILE"; exit 1; fi


# --- Source All Configuration from JSON ---
S3_BUCKET_NAME=$(jq -r '.s3_bucket_name' "$CONFIG_FILE")
BACKUP_BACKEND=$(jq -r '.backup_backend // "s3"' "$CONFIG_FILE")
HOSTNAME=$(hostname -s)
TMP_RESTORE_DIR="/tmp/backup_verify_$$"
TMP_KEY_FILE=""


# --- Cleanup Function ---
cleanup() {
    log_info "Cleaning up temporary files..."
    if [ -n "$TMP_KEY_FILE" ]; then rm -f "$TMP_KEY_FILE"; fi
    if [ -d "$TMP_RESTORE_DIR" ]; then rm -rf "$TMP_RESTORE_DIR"; fi
}
trap cleanup EXIT


# --- Main Logic ---
log_info "--- Starting Backup Verification Process ---"

if [ "$(id -u)" -ne 0 ]; then log_error "This script must be run as root."; exit 1; fi

if [ "$BACKUP_BACKEND" != "s3" ]; then
    log_error "Backup verification only supports the 's3' backend."
    exit 1
fi

# 1. Find the latest backup set
log_info "Searching for the latest backup set in s3://${S3_BUCKET_NAME}/${HOSTNAME}/..."
LATEST_BACKUP_TS=$(aws s3 ls "s3://${S3_BUCKET_NAME}/${HOSTNAME}/" | grep 'PRE' | awk '{print $2}' | sed 's/\///' | sort -r | head -n 1)

if [ -z "$LATEST_BACKUP_TS" ]; then
    log_error "No backups found for host '${HOSTNAME}' in bucket '${S3_BUCKET_NAME}'."
    exit 1
fi
log_success "Found latest backup set: ${LATEST_BACKUP_TS}"


# 2. Verify the manifest
log_info "Verifying manifest for backup set ${LATEST_BACKUP_TS}..."
MANIFEST_S3_PATH="s3://${S3_BUCKET_NAME}/${HOSTNAME}/${LATEST_BACKUP_TS}/backup_manifest.json"
MANIFEST_JSON=$(aws s3 cp "$MANIFEST_S3_PATH" - 2>/dev/null)

if ! echo "$MANIFEST_JSON" | jq -e . > /dev/null 2>&1; then
    log_error "Failed to download or parse a valid manifest from ${MANIFEST_S3_PATH}."
    log_error "The backup set may be corrupt, incomplete, or there could be an S3 permissions issue."
    exit 1
fi
log_success "Manifest is valid JSON and readable."


# 3. Find a sample data file to test
log_info "Searching for a sample data file to verify..."
SAMPLE_ARCHIVE=$(aws s3 ls "s3://${S3_BUCKET_NAME}/${HOSTNAME}/${LATEST_BACKUP_TS}/" --recursive | grep '\.tar\.gz\.enc$' | head -n 1 | awk '{print $4}')

if [ -z "$SAMPLE_ARCHIVE" ]; then
    log_warn "Could not find any data archives (.tar.gz.enc) in the backup set. The backup might be empty."
    # This isn't a hard failure, but it's not a full success either.
    log_success "--- Verification Finished: Manifest is OK, but no data files found to test. ---"
    exit 0
fi
log_info "Selected sample file for verification: $SAMPLE_ARCHIVE"


# 4. Perform decryption and integrity check
log_info "Performing decryption and integrity check on the sample file..."

mkdir -p "$TMP_RESTORE_DIR"

TMP_KEY_FILE=$(mktemp)
chmod 600 "$TMP_KEY_FILE"
ENCRYPTION_KEY=$(jq -r '.encryption_key' "$CONFIG_FILE")
if [ -z "$ENCRYPTION_KEY" ] || [ "$ENCRYPTION_KEY" == "null" ]; then
    log_error "encryption_key is empty or not found in $CONFIG_FILE"
    exit 1
fi
echo -n "$ENCRYPTION_KEY" > "$TMP_KEY_FILE"

# Create a pipeline to download, decrypt, and test the tarball without saving intermediate files
if ! aws s3 cp "s3://${S3_BUCKET_NAME}/${SAMPLE_ARCHIVE}" - | \
    openssl enc -d -aes-256-cbc -salt -pbkdf2 -md sha256 -pass "file:$TMP_KEY_FILE" | \
    tar -zt > /dev/null; then
    
    pipeline_status=("${PIPESTATUS[@]}")
    log_error "Backup verification FAILED."
    if [ ${pipeline_status[0]} -ne 0 ]; then
        log_error "Step 1 (aws s3 cp) failed. Could not download sample file."
    elif [ ${pipeline_status[1]} -ne 0 ]; then
        log_error "Step 2 (openssl) failed. This likely means the encryption key is INCORRECT or the file is corrupt."
    elif [ ${pipeline_status[2]} -ne 0 ]; then
        log_error "Step 3 (tar) failed. The archive is corrupt or in an unexpected format."
    fi
    exit 1
fi

log_success "Successfully downloaded, decrypted, and verified the integrity of the sample archive."
log_success "--- Backup Verification Finished Successfully ---"

exit 0
