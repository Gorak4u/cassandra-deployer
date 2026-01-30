#!/bin/bash
# DEPRECATED: This script is a wrapper for backward compatibility.
# The recommended method is to use 'cassy.sh --rolling-op restart ...'
set -euo pipefail

usage() {
    echo "Usage: $0 \"<qv_query>\""
    echo
    echo "Example: $0 \"-r role_cassandra_pfpt -d AWSLAB\""
    echo "This is a deprecated wrapper. Use 'cassy.sh --rolling-op restart \"<qv_query>\"' instead."
    exit 1
}

if [[ -z "$1" || "$1" == "-h" || "$1" == "--help" ]]; then
    usage
fi

QV_QUERY="$1"

echo "INFO: Running rolling restart via 'cassy.sh --rolling-op restart'..."

./scripts/cassy.sh --rolling-op restart --qv-query "${QV_QUERY}"

echo "Rolling restart process completed."
