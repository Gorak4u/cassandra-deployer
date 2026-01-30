#!/bin/bash
# Performs a safe, rolling restart of Cassandra nodes.
# It uses cassy.sh with an inter-node health check.
set -euo pipefail

# The path to the inter-node health check script.
HEALTH_CHECK_SCRIPT="./scripts/check_cluster_health.sh"

usage() {
    echo "Usage: $0 \"<qv_query>\""
    echo
    echo "Example: $0 \"-r role_cassandra_pfpt -d AWSLAB\""
    echo "This will perform a rolling restart on all nodes returned by the qv query,"
    echo "running a health check between each node."
    exit 1
}

if [[ -z "$1" || "$1" == "-h" || "$1" == "--help" ]]; then
    usage
fi

QV_QUERY="$1"

if [ ! -f "$HEALTH_CHECK_SCRIPT" ]; then
    echo "Health check script not found at: ${HEALTH_CHECK_SCRIPT}"
    exit 1
fi
if [ ! -x "$HEALTH_CHECK_SCRIPT" ]; then
    chmod +x "$HEALTH_CHECK_SCRIPT"
    echo "Made health check script executable: ${HEALTH_CHECK_SCRIPT}"
fi


echo "Starting a safe rolling restart for nodes matching query: '${QV_QUERY}'"
echo "A health check will be performed after each node restart."

./scripts/cassy.sh --qv-query "${QV_QUERY}" \
  -c "sudo /usr/local/bin/cass-ops restart" \
  --inter-node-check "${HEALTH_CHECK_SCRIPT}"

echo "Rolling restart process completed."
