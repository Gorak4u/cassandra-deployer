# Firebase Studio

This is a NextJS starter in Firebase Studio.

To get started, take a look at src/app/page.tsx.

---

## External Cluster Orchestration

A standalone orchestration script is available at `scripts/cluster-run.sh`. This script is designed to be run from an external management node or CI/CD system like Jenkins to execute commands across the entire cluster.

### Prerequisites

The machine running the script must have **passwordless SSH access** (e.g., via SSH keys) to all Cassandra nodes in the cluster for the specified user.

### Usage

The script can run any command or execute a local script file on your cluster nodes, either sequentially (default) or in parallel.

**Examples:**

```bash
# Get the status from all nodes, one by one
./scripts/cluster-run.sh --nodes "node1.example.com,node2.example.com,node3.example.com" -c "sudo cass-ops health"

# Run a full repair on the entire cluster in parallel, using a file for the node list
./scripts/cluster-run.sh --nodes-file /path/to/my_nodes.txt --parallel -c "sudo cass-ops repair"

# Execute a local diagnostic script on a single node
./scripts/cluster-run.sh --node "node1.example.com" -s ./my_local_check.sh
```

For all options, run the script with the `--help` flag:
```bash
./scripts/cluster-run.sh --help
```
