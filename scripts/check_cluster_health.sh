#!/bin/bash
# A health check script for cassy.sh's --inter-node-check.
# It checks the overall cluster status by querying a specific seed node.
# It includes retry logic to handle transient issues.

set -euo pipefail

# --- Configuration ---
# The seed node to use as the "canary" for the health check.
# In a real environment, this should be a reliable, known seed node.
# You can also use an environment variable: SEED_NODE=${SEED_NODE:-"cassandra-seed-1.example.com"}
SEED_NODE="cassandra-seed-1.example.com" 
MAX_RETRIES=3
RETRY_DELAY=15 # seconds

# The cassy.sh script passes the hostname of the node that was just operated on as $1.
# We don't need it for this global health check, but we acknowledge it.
NODE_OPERATED_ON=${1:-"N/A"}

echo "[Health Check] Verifying cluster health after operation on ${NODE_OPERATED_ON}."

for i in $(seq 1 $MAX_RETRIES); do
  echo "[Health Check] Attempt $i of $MAX_RETRIES: Running 'cass-ops cluster-health' against ${SEED_NODE}..."
  
  # We use cassy.sh to run the command on the remote seed node.
  # The cluster-health script itself will exit non-zero on failure.
  if ./scripts/cassy.sh --node "${SEED_NODE}" -c "sudo /usr/local/bin/cass-ops cluster-health --silent"; then
    echo "[Health Check] Cluster health check passed."
    exit 0 # Success
  fi
  
  if [ "$i" -lt "$MAX_RETRIES" ]; then
    echo "[Health Check] Health check failed. Retrying in $RETRY_DELAY seconds..."
    sleep $RETRY_DELAY
  else
    echo "[Health Check] CRITICAL: Health check failed after $MAX_RETRIES attempts. Halting rolling operation."
    exit 1 # Failure
  fi
done
