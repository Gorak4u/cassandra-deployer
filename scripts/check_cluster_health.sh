#!/bin/bash
# A health check script for cassy.sh's --inter-node-check.
# It performs a multi-step verification to ensure a node and the cluster
# are healthy before allowing a rolling operation to proceed.

set -euo pipefail

# --- Configuration ---
NODE_OPERATED_ON=${1:-}
MAX_RETRIES=12 # Total attempts
RETRY_DELAY=15 # Seconds to wait between full check cycles

if [ -z "$NODE_OPERATED_ON" ]; then
    echo "[Health Check] ERROR: The hostname of the node that was operated on must be provided as the first argument." >&2
    exit 1
fi

echo "[Health Check] Verifying health and cluster stability after operation on ${NODE_OPERATED_ON}."

for i in $(seq 1 $MAX_RETRIES); do
    echo "[Health Check] Full check cycle, attempt $i of $MAX_RETRIES..."

    # Check 1: Ping the node that was operated on.
    echo "  [1/3] Pinging ${NODE_OPERATED_ON}..."
    if ! ping -c 3 "${NODE_OPERATED_ON}"; then
        echo "    - FAIL: Node is not responding to ping. Will retry after ${RETRY_DELAY}s." >&2
        sleep $RETRY_DELAY
        continue
    fi
    echo "    - OK: Node is reachable on the network."

    # Check 2: Check for SSH connectivity. We use cassy.sh to run a simple echo.
    # This reuses the user/auth logic from the main script.
    echo "  [2/3] Verifying SSH connectivity to ${NODE_OPERATED_ON}..."
    if ! ./scripts/cassy.sh --node "${NODE_OPERATED_ON}" -c "echo 'SSH OK'" >/dev/null 2>&1; then
        echo "    - FAIL: Cannot connect via SSH. The SSH daemon may still be starting. Will retry after ${RETRY_DELAY}s." >&2
        sleep $RETRY_DELAY
        continue
    fi
    echo "    - OK: SSH is responsive."

    # Check 3: Check the health of the service on the node that was just operated on.
    # This ensures Cassandra itself is up and that it sees the cluster as healthy from its perspective.
    echo "  [3/3] Verifying service and cluster health on ${NODE_OPERATED_ON}..."
    if ./scripts/cassy.sh --node "${NODE_OPERATED_ON}" -c "sudo /usr/local/bin/cass-ops cluster-health --silent"; then
        echo "[Health Check] SUCCESS: All checks passed. Cluster is stable and ready for the next operation."
        exit 0
    fi

    echo "    - FAIL: Health check on the node itself failed. The service may not be fully initialized or may not see the cluster as healthy. Will retry after ${RETRY_DELAY}s." >&2
    sleep $RETRY_DELAY
done

# If the loop finishes without a successful check
echo "[Health Check] CRITICAL: Health check failed after $MAX_RETRIES attempts. Halting rolling operation to ensure cluster safety." >&2
exit 1
