
export const healthScripts = {
      'cluster-health.sh': '#!/bin/bash\\nnodetool status',
      'disk-health-check.sh': `#!/bin/bash

set -euo pipefail

# These are defaults if not passed via flags.
CASSANDRA_DATADIR=/var/lib/cassandra/data
WARNING_THRESHOLD=30
CRITICAL_THRESHOLD=15

# Color codes
RESET="\\e[0m"
BOLD="\\e[1m"
COL_RED="\\e[31m"
COL_YELLOW="\\e[33m"

function usage() {
  cat<<EOF
usage: $0 [OPTIONS]

Checks the available disk space for a directory (defaults to '$CASSANDRA_DATADIR') against given thresholds.
Thresholds are percentages of FREE space.

Flags:
   -p PATH  Path to check disk space for. Default: $CASSANDRA_DATADIR
   -w INT   Warning threshold (percent free). Default: $WARNING_THRESHOLD
   -c INT   Critical threshold (percent free). Default: $CRITICAL_THRESHOLD
   -h       Show this help message.

Exit Codes:
 0: Disk space is sufficient.
 1: Disk space is below the warning threshold.
 2: Disk space is below the critical threshold.
 3: Script failed to get disk space information.
EOF
}

function warning() {
  local msg="$@"
  printf "$BOLD$COL_YELLOW""WARNING: $msg""$RESET\\n" >&2
}

function error() {
  local msg="$@"
  printf "$BOLD$COL_RED""ERROR: $msg""$RESET\\n" >&2
}

function get_free_disk_space() {
  local mountpoint="$1"
  local used_percent
  
  used_percent=$(df "$mountpoint" --output=pcent | tail -1 | tr -cd '[:digit:]')
  rc=$?

  if [[ -z "$used_percent" ]] || [[ $rc != 0 ]]; then
    error "Failed to get disk space for path '$mountpoint'."
    exit 3
  fi

  echo $(( 100 - used_percent ))
}

# --- Main Logic ---
while getopts "hp:w:c:" arg; do
  case $arg in
    h)
      usage
      exit 0
      ;;
    p)
      CASSANDRA_DATADIR=$OPTARG
      ;;
    w)
      WARNING_THRESHOLD=$OPTARG
      ;;
    c)
      CRITICAL_THRESHOLD=$OPTARG
      ;;
    *)
      usage
      exit 1
      ;;
  esac
done

free_space=$(get_free_disk_space "$CASSANDRA_DATADIR")
exit_code=$?

if [[ $free_space -lt $CRITICAL_THRESHOLD ]]; then
  error "Free disk space for '$CASSANDRA_DATADIR' is $free_space%, which is below the critical threshold of $CRITICAL_THRESHOLD%."
  exit 2
fi

if [[ $free_space -lt $WARNING_THRESHOLD ]]; then
  warning "Free disk space for '$CASSANDRA_DATADIR' is $free_space%, which is below the warning threshold of $WARNING_THRESHOLD%."
  exit 1
fi

printf "OK: Free disk space for '$CASSANDRA_DATADIR' is $free_space%%, which is above all thresholds.\\n"
exit 0
`,
      'node_health_check.sh': `#!/bin/bash
set -e

log_message() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] \$1"
}

log_ok() {
  log_message "OK: \$1"
}

log_error() {
  log_message "ERROR: \$1"
  exit 1
}

log_warning() {
  log_message "WARNING: \$1"
}

log_message "--- Starting Node Health Check ---"
LOCAL_IP=$(hostname -i)

# 1. Disk Space Check
log_message "1. Checking disk space..."
if ! /usr/local/bin/disk-health-check.sh; then
    log_error "Disk space check failed. See output from disk-health-check.sh."
else
    log_ok "Disk space is sufficient."
fi

# 2. Node Status Check
log_message "2. Checking local node status..."
NODE_STATUS=$(nodetool status | grep "\$LOCAL_IP" | awk '{print \$1}')

if [ "\$NODE_STATUS" == "UN" ]; then
    log_ok "Node status is UN (Up/Normal)."
elif [ -z "\$NODE_STATUS" ]; then
    log_error "Could not find local node IP (\$LOCAL_IP) in nodetool status output."
else
    log_error "Node status is '\$NODE_STATUS', not UN."
fi

# 3. Gossip Check
log_message "3. Checking gossip status..."
GOSSIP_STATUS=$(nodetool gossipinfo | grep "STATUS" | grep "\$LOCAL_IP" | cut -d':' -f2)
if [[ "\$GOSSIP_STATUS" == "NORMAL" ]]; then
    log_ok "Gossip state is NORMAL."
else
    log_warning "Gossip state is '\$GOSSIP_STATUS', not NORMAL. This might be temporary."
fi

# 4. Check for active streams
log_message "4. Checking for network streams..."
if ! nodetool netstats | grep -q "Mode: NORMAL"; then
    log_warning "Node is not in NORMAL mode. It might be streaming, joining, or leaving."
    nodetool netstats
else
    log_ok "Network mode is NORMAL."
fi

# 5. Check for exceptions in the log
log_message "5. Scanning system log for recent exceptions..."
if journalctl -u cassandra -S "10 minutes ago" | grep -q "Exception"; then
    log_warning "Found 'Exception' in Cassandra logs from the last 10 minutes. Please review logs manually."
    journalctl -u cassandra -S "10 minutes ago" | grep "Exception" | tail -n 10
else
    log_ok "No recent exceptions found in logs."
fi

log_message "--- Node Health Check Completed ---"
`,
      'version-check.sh': `#!/bin/bash
set -euo pipefail

log_message() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] \$1"
}

log_message "--- Checking Cassandra versions across the cluster ---"

# Get versions from nodetool status, ignoring the header, and extract the version column (8th column)
VERSIONS=$(nodetool status | tail -n +6 | head -n -1 | awk '{print \$8}')

if [ -z "\$VERSIONS" ]; then
    log_message "ERROR: Could not retrieve version information from 'nodetool status'."
    exit 1
fi

# Count the number of unique versions
UNIQUE_VERSIONS_COUNT=$(echo "\$VERSIONS" | sort -u | wc -l)

if [ "\$UNIQUE_VERSIONS_COUNT" -eq 1 ]; then
    UNIQUE_VERSION=$(echo "\$VERSIONS" | sort -u)
    log_message "OK: All nodes are running the same Cassandra version: \$UNIQUE_VERSION"
    exit 0
else
    log_message "ERROR: Inconsistent Cassandra versions found in the cluster!"
    log_message "Unique versions found:"
    echo "\$VERSIONS" | sort | uniq -c
    exit 1
fi
`,
};
