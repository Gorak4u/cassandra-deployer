# Firebase Studio

This is a NextJS starter in Firebase Studio.

To get started, take a look at src/app/page.tsx.

---

## External Cluster Orchestration (`cassy.sh`)

A standalone orchestration script is available at `scripts/cassy.sh`. This script is designed to be run from an external management node or CI/CD system like Jenkins to execute commands across the entire cluster. It does not get deployed to the Cassandra nodes themselves.

### Prerequisites

The machine running the script must have:
*   **Passwordless SSH access** (e.g., via SSH keys) to all target Cassandra nodes for the specified user.
*   The `jq` utility installed if using the `--json` output format.
*   The `timeout` utility (part of `coreutils`) if using the `--timeout` feature.

### Usage

The script can run any command or execute a local script file on your cluster nodes. Nodes can be specified statically or discovered dynamically using the `qv` inventory tool.

### Options

| Flag | Argument | Description |
|---|---|---|
| `-n`, `--nodes` | `<list>` | A comma-separated list of target node hostnames or IPs. |
| `-f`, `--nodes-file` | `<path>` | A file containing a list of target nodes, one per line. |
| `--node` | `<host>` | Specify a single target node. |
| `--qv-query` | `"<query>"` | A quoted string of 'qv' flags to dynamically fetch a node list. |
| `-c`, `--command` | `<command>` | The shell command to execute on each node. |
| `-s`, `--script` | `<path>` | The path to a local script to copy and execute on each node. |
| `-l`, `--user` | `<user>` | The SSH user to connect as. Defaults to the current user. |
| `-P`, `--parallel` | | Execute on all nodes in parallel instead of sequentially. |
| `--ssh-options` | `<opts>` | Quoted string of additional options for the SSH command (e.g., "-i /path/key.pem"). |
| `--dry-run` | | Show which nodes would be targeted and what command would run, without executing. |
| `--json` | | Output results in a machine-readable JSON format. |
| `--timeout` | `<seconds>` | Set a timeout in seconds for the command on each node. `0` for no timeout. |
| `--output-dir`| `<path>` | Save the output from each node to a separate file in the specified directory. |
| `-h`, `--help` | | Show the help message. |


### Examples

**Static Node Lists:**
```bash
# Get the status from a specific list of nodes, one by one
./scripts/cassy.sh --nodes "node1.example.com,node2.example.com" -c "sudo cass-ops health"

# Run a full repair on the entire cluster in parallel, using a file for the node list
./scripts/cassy.sh --nodes-file /path/to/my_nodes.txt --parallel -c "sudo cass-ops repair"

# Execute a local diagnostic script on a single node
./scripts/cassy.sh --node "node1.example.com" -s ./my_local_check.sh
```

**Dynamic Inventory with `qv`:**
If your management node has the `qv` inventory tool, you can use it to fetch the list of nodes dynamically.

```bash
# Get the hostname from all Cassandra nodes in the SC4 datacenter
./scripts/cassy.sh --qv-query "-r role_cassandra_pfpt -d SC4" -c "hostname"

# Run a cluster health check on all Cassandra nodes in the AWSLAB datacenter in parallel
./scripts/cassy.sh --qv-query "-r role_cassandra_pfpt -d AWSLAB" -P -c "sudo cass-ops cluster-health"
```

**Advanced Usage:**
```bash
# Dry run: see what would happen without executing
./scripts/cassy.sh --qv-query "-r role_cassandra_pfpt" --dry-run -c "sudo reboot"

# JSON output: get machine-readable results for automation
./scripts/cassy.sh --nodes "node1,node2" --json -c "sudo cass-ops health"

# Save output: log the output of each node to a separate file in the 'logs' directory
./scripts/cassy.sh --nodes "node1,node2" --output-dir ./logs -c "cat /var/log/cassandra/system.log"

# Timeout: run a command but kill it if it takes longer than 5 minutes
./scripts/cassy.sh --node "node1" --timeout 300 -c "sudo cass-ops repair -k my_large_keyspace"
```

For all options, run the script with the `--help` flag:
```bash
./scripts/cassy.sh --help
```
