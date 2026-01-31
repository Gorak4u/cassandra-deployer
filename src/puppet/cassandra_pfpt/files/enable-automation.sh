#!/bin/bash
# This file is managed by Puppet.
# Removes flag files and re-enables the Puppet agent service to resume automation.

set -euo pipefail

# --- Color Codes ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

PUPPET_FLAG_FILE="/var/lib/puppet-disabled"
REPAIR_FLAG_FILE="/var/lib/repair-disabled"

echo -e "${GREEN}--- Re-enabling Automated Operations ---${NC}"

# Enable cron-based Puppet runs
if [ -f "$PUPPET_FLAG_FILE" ]; then
    echo "Removing cron-based Puppet run block..."
    rm -f "$PUPPET_FLAG_FILE"
    echo "Flag file removed."
else
    echo "Cron-based Puppet runs were already enabled."
fi

# Enable the Puppet agent service directly
if command -v puppet &> /dev/null; then
    echo "Enabling Puppet agent service..."
    puppet agent --enable
else
    echo -e "${YELLOW}WARNING: 'puppet' command not found. Skipping direct agent enable.${NC}"
fi

# Enable scheduled repairs
if [ -f "$REPAIR_FLAG_FILE" ]; then
    echo "Re-enabling scheduled repairs..."
    rm -f "$REPAIR_FLAG_FILE"
    echo "Scheduled repairs enabled."
else
    echo "Scheduled repairs were already enabled."
fi

echo -e "${GREEN}--- Automation Enabled Successfully ---${NC}"

exit 0
