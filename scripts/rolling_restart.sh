#!/bin/bash
#
# LEGACY WRAPPER for cassy.sh
#
# This is a backward-compatibility wrapper for the --rolling-op feature in cassy.sh.
# It is recommended to use 'cassy.sh --rolling-op restart' directly.
#
# All arguments passed to this script will be forwarded to cassy.sh.
#
# Example:
#   ./scripts/rolling_restart.sh --qv-query "-r role_cassandra_pfpt -d AWSLAB"

set -euo pipefail

echo "INFO: Using legacy wrapper. It is recommended to use 'cassy.sh --rolling-op restart' directly." >&2

# Get the directory where this script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

# Execute the main cassy.sh script with the rolling-op and pass all other arguments through
exec "${SCRIPT_DIR}/cassy.sh" --rolling-op restart "$@"
