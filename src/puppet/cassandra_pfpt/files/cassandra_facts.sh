#!/bin/bash
# This file is managed by Puppet.
#
# /etc/puppetlabs/facter/facts.d/cassandra_facts.sh
#
# This is an External Fact script for Facter. It provides facts about the
# local Cassandra node's status, configuration, and resource usage.
#
# These facts will be available in Puppet as, e.g., $facts['cassandra_node_status'].

# --- Pre-flight Checks ---
# Exit if key tools are not present
if ! command -v nodetool &> /dev/null || ! command -v jq &> /dev/null || ! command -v pgrep &>/dev/null; then
    exit 0
fi

# Exit if Cassandra is not running
if ! pgrep -f 'java.*org.apache.cassandra.service.CassandraDaemon' > /dev/null; then
    exit 0
fi

CONFIG_FILE="/etc/backup/config.json"
JVM_OPTS_FILE="/etc/cassandra/conf/jvm-server.options"
RACKDC_PROPS="/etc/cassandra/conf/cassandra-rackdc.properties"
CASSANDRA_YAML="/etc/cassandra/conf/cassandra.yaml"
JMX_PASS_FILE="/etc/cassandra/jmxremote.password"

if [ ! -f "$CONFIG_FILE" ] || [ ! -f "$JVM_OPTS_FILE" ] || [ ! -f "$CASSANDRA_YAML" ]; then
    exit 0
fi

# --- Get Config Values ---
CASSANDRA_USER=$(jq -r '.cassandra_user // "cassandra"' "$CONFIG_FILE" 2>/dev/null)
if [ -z "$CASSANDRA_USER" ] || [ "$CASSANDRA_USER" == "null" ]; then
    CASSANDRA_USER="cassandra"
fi

LOCAL_IP=$(jq -r '.listen_address' "$CONFIG_FILE" 2>/dev/null)
if [ -z "$LOCAL_IP" ] || [ "$LOCAL_IP" == "null" ]; then
    LOCAL_IP=$(hostname -I | awk '{print $1}')
fi

if [ -z "$LOCAL_IP" ]; then
    exit 0
fi

# --- Helper Function ---
# Safely get a value from a command, running as the C* user.
get_value() {
    local cmd="$1"
    local result
    # Facter runs as root, so we can su to the cassandra user.
    # This ensures the command has the correct environment and permissions.
    result=$(su -s /bin/bash "$CASSANDRA_USER" -c "$cmd" 2>/dev/null)
    if [ $? -eq 0 ] && [ -n "$result" ]; then
        echo "$result"
    fi
}

# --- Determine JMX Auth and build nodetool command ---
NODETOOL_CMD="nodetool"
if grep -q -- '-Dcom.sun.management.jmxremote.authenticate=true' "$JVM_OPTS_FILE"; then
    if [ -f "$JMX_PASS_FILE" ]; then
        # Look for the 'monitorRole' and get its password.
        JMX_USER=$(awk '/monitorRole/ {print $1}' "$JMX_PASS_FILE")
        JMX_PASS=$(awk '/monitorRole/ {print $2}' "$JMX_PASS_FILE")
        if [ -n "$JMX_USER" ] && [ -n "$JMX_PASS" ]; then
             NODETOOL_CMD="nodetool -u $JMX_USER -pw $JMX_PASS"
        fi
    fi
fi

# --- Gather Facts ---

# 1. Status & Health Facts (use get_value to run as cassandra user)
echo "cassandra_node_status=$(get_value "$NODETOOL_CMD status | awk -v ip=\"$LOCAL_IP\" '\$2 == ip {print \$1}'")"
echo "cassandra_schema_version=$(get_value "$NODETOOL_CMD describecluster | grep 'Schema versions:' | awk '{print \$NF}' | tr -d '[]' | cut -d',' -f1")"
echo "cassandra_uptime_seconds=$(get_value "$NODETOOL_CMD info | grep 'Uptime (seconds)' | awk '{print \$3}'")"

# 2. Configuration & Identity Facts
# `nodetool version` does not require JMX, but running it as the C* user is safer.
echo "cassandra_version=$(get_value "nodetool version | grep 'ReleaseVersion' | awk '{print \$2}'")"
echo "cassandra_cluster_name=$(get_value "$NODETOOL_CMD describecluster | grep 'Name:' | awk '{print \$2}'")"

# These facts don't need nodetool, so they are more reliable.
if [ -f "$RACKDC_PROPS" ]; then
    DC=$(grep '^dc=' "$RACKDC_PROPS" | cut -d'=' -f2)
    RACK=$(grep '^rack=' "$RACKDC_PROPS" | cut -d'=' -f2)
    if [ -n "$DC" ]; then echo "cassandra_datacenter=$DC"; fi
    if [ -n "$RACK" ]; then echo "cassandra_rack=$RACK"; fi
fi

# Check if this node is a seed (read from cassandra.yaml)
SEEDS=$(grep 'seeds:' "$CASSANDRA_YAML" | sed 's/.*seeds: "//' | sed 's/"//' || echo "")
if [[ "$SEEDS" == *"$LOCAL_IP"* ]]; then
    echo "cassandra_is_seed=true"
else
    echo "cassandra_is_seed=false"
fi

# 3. Resource Usage Facts
# These also don't need nodetool.
DATA_DIR=$(jq -r '.cassandra_data_dir' "$CONFIG_FILE" 2>/dev/null)
COMMITLOG_DIR=$(jq -r '.commitlog_dir' "$CONFIG_FILE" 2>/dev/null)

if [ -n "$DATA_DIR" ] && [ "$DATA_DIR" != "null" ] && [ -d "$DATA_DIR" ]; then
    USED_PERCENT=$(df "$DATA_DIR" --output=pcent | tail -1 | tr -cd '[:digit:]' || echo "")
    if [ -n "$USED_PERCENT" ]; then
        echo "cassandra_data_disk_usage_percent=$USED_PERCENT"
    fi
fi
if [ -n "$COMMITLOG_DIR" ] && [ "$COMMITLOG_DIR" != "null" ] && [ -d "$COMMITLOG_DIR" ]; then
    USED_PERCENT=$(df "$COMMITLOG_DIR" --output=pcent | tail -1 | tr -cd '[:digit:]' || echo "")
    if [ -n "$USED_PERCENT" ]; then
        echo "cassandra_commitlog_disk_usage_percent=$USED_PERCENT"
    fi
fi
