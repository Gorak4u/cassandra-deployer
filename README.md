# Firebase Studio

This is a NextJS starter in Firebase Studio.

To get started, take a look at src/app/page.tsx.

---

## External Cluster Orchestration (`cluster-run.sh`)

A standalone orchestration script is available at `scripts/cluster-run.sh`. This script is designed to be run from an external management node or CI/CD system like Jenkins to execute commands across the entire cluster. It does not get deployed to the Cassandra nodes themselves.

### Prerequisites

The machine running the script must have **passwordless SSH access** (e.g., via SSH keys) to all target Cassandra nodes for the specified user.

### Usage

The script can run any command or execute a local script file on your cluster nodes, either sequentially (default) or in parallel. Nodes can be specified statically or discovered dynamically using the `qv` inventory tool.

### Examples

**Static Node Lists:**
```bash
# Get the status from a specific list of nodes, one by one
./scripts/cluster-run.sh --nodes "node1.example.com,node2.example.com" -c "sudo cass-ops health"

# Run a full repair on the entire cluster in parallel, using a file for the node list
./scripts/cluster-run.sh --nodes-file /path/to/my_nodes.txt --parallel -c "sudo cass-ops repair"

# Execute a local diagnostic script on a single node
./scripts/cluster-run.sh --node "node1.example.com" -s ./my_local_check.sh
```

**Dynamic Inventory with `qv`:**
If your management node has the `qv` inventory tool, you can use it to fetch the list of nodes dynamically.

```bash
# Get the hostname from all Cassandra nodes in the SC4 datacenter
./scripts/cluster-run.sh --qv-query "-r role_cassandra_pfpt -d SC4" -c "hostname"

# Run a cluster health check on all Cassandra nodes in the AWSLAB datacenter in parallel
./scripts/cluster-run.sh --qv-query "-r role_cassandra_pfpt -d AWSLAB" -P -c "sudo cass-ops cluster-health"
```

For all options, run the script with the `--help` flag:
```bash
./scripts/cluster-run.sh --help
```
