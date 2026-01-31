#!/bin/bash
# This file is managed by Puppet.
# Removes flag files to re-enable Puppet and automated repairs.

set -euo pipefail

# --- Color Codes ---
GREEN='\033[0;32m'
NC='\033[0m' # No Color

PUPPET_FLAG_FILE="/var/lib/puppet-disabled"
REPAIR_FLAG_FILE="/var/lib/repair-disabled"

echo -e "${GREEN}--- Re-enabling Automated Operations ---${NC}"

if [ -f "$PUPPET_FLAG_FILE" ]; then
    echo "Re-enabling Puppet agent cron job..."
    rm -f "$PUPPET_FLAG_FILE"
    echo "Puppet agent enabled."
else
    echo "Puppet agent was already enabled."
fi

if [ -f "$REPAIR_FLAG_FILE" ]; then
    echo "Re-enabling scheduled repairs..."
    rm -f "$REPAIR_FLAG_FILE"
    echo "Scheduled repairs enabled."
else
    echo "Scheduled repairs were already enabled."
fi

echo -e "${GREEN}--- Automation Enabled Successfully ---${NC}"

exit 0
