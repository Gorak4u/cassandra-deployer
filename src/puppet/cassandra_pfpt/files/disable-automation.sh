#!/bin/bash
# This file is managed by Puppet.
# Creates flag files to temporarily disable Puppet and automated repairs.

set -euo pipefail

# --- Color Codes ---
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

PUPPET_FLAG_FILE="/var/lib/puppet-disabled"
REPAIR_FLAG_FILE="/var/lib/repair-disabled"
MESSAGE="${1:-"Automation disabled by operator at $(date)"}"

echo -e "${YELLOW}--- Disabling Automated Operations ---${NC}"

echo -e "Disabling Puppet agent cron job..."
echo "$MESSAGE" > "$PUPPET_FLAG_FILE"
echo -e "Puppet agent disabled. Flag file created at ${PUPPET_FLAG_FILE}"

echo -e "Disabling scheduled repairs..."
echo "$MESSAGE" > "$REPAIR_FLAG_FILE"
echo -e "Scheduled repairs disabled. Flag file created at ${REPAIR_FLAG_FILE}"

echo -e "${GREEN}--- Automation Disabled Successfully ---${NC}"
echo -e "To re-enable, run: sudo cass-ops enable-automation"

exit 0
