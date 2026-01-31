#!/bin/bash
# This file is managed by Puppet.
# Creates flag files and disables the Puppet agent service to temporarily halt automation.

set -euo pipefail

# --- Color Codes ---
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

PUPPET_FLAG_FILE="/var/lib/puppet-disabled"
REPAIR_FLAG_FILE="/var/lib/repair-disabled"
MESSAGE="${1:-"Automation disabled by operator at $(date)"}"

echo -e "${YELLOW}--- Disabling Automated Operations ---${NC}"

# Disable via flag file for cron-based runs
echo -e "Creating flag file to block cron-based Puppet runs..."
echo "$MESSAGE" > "$PUPPET_FLAG_FILE"
echo -e "Flag file created at ${PUPPET_FLAG_FILE}"

# Disable the puppet agent service directly
if command -v puppet &> /dev/null; then
    echo -e "Disabling Puppet agent service..."
    puppet agent --disable "$MESSAGE"
else
    echo -e "${YELLOW}WARNING: 'puppet' command not found. Skipping direct agent disable.${NC}"
fi

echo -e "Disabling scheduled repairs..."
echo "$MESSAGE" > "$REPAIR_FLAG_FILE"
echo -e "Scheduled repairs disabled. Flag file created at ${REPAIR_FLAG_FILE}"

echo -e "${GREEN}--- Automation Disabled Successfully ---${NC}"
echo -e "To re-enable, run: sudo cass-ops enable-automation"

exit 0
