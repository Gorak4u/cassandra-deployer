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
| `-P`, `--parallel` | `[N]` | Execute in parallel. By default on all nodes, or with a concurrency of N if provided. |
| `--ssh-options` | `<opts>` | Quoted string of additional options for the SSH command (e.g., "-i /path/key.pem"). |
| `--dry-run` | | Show which nodes would be targeted and what command would run, without executing. |
| `--json` | | Output results in a machine-readable JSON format. |
| `--timeout` | `<seconds>` | Set a timeout in seconds for the command on each node. `0` for no timeout. |
| `--output-dir`| `<path>` | Save the output from each node to a separate file in the specified directory. |
| `-h`, `--help` | | Show the help message. |


### Production Cassandra Operations with `cassy.sh`

This section provides recipes for common, production-level Cassandra maintenance tasks using `cassy.sh`.

#### **Pattern 1: Safe Rolling Restart of a Datacenter**
A rolling restart is a common maintenance task. It must be done sequentially to ensure the cluster remains available. `cassy.sh`'s default sequential mode is perfect for this, as the on-node `cass-ops restart` script waits for the node to become healthy before exiting.

```bash
# Restart all Cassandra nodes in the AWSLAB datacenter, one by one.
./scripts/cassy.sh --qv-query "-r role_cassandra_pfpt -d AWSLAB" -c "sudo cass-ops restart"
```

#### **Pattern 2: Parallel Cluster-Wide Repair**
Unlike restarts, `nodetool repair` is safe to run in parallel across the cluster. For very large clusters, it's best practice to run it per-datacenter to control cross-datacenter network traffic. You can also use batch-mode parallel execution to limit the impact.

```bash
# Run repair on all Cassandra nodes in the SC4 datacenter simultaneously.
./scripts/cassy.sh --qv-query "-r role_cassandra_pfpt -d SC4" --parallel -c "sudo cass-ops repair"

# Run repair in batches of 5 nodes at a time.
./scripts/cassy.sh --qv-query "-r role_cassandra_pfpt -d SC4" --parallel 5 -c "sudo cass-ops repair"
```

#### **Pattern 3: Cluster-Wide Health Auditing**
You can use `cassy.sh` with the `--json` flag to programmatically audit your cluster's health and parse the results, which is ideal for automation.

```bash
# Get health status from all nodes and use jq to print the details of any failed checks.
./scripts/cassy.sh --qv-query "-r role_cassandra_pfpt" --json -c "sudo cass-ops health --json" | jq '.results[] | select(.status == "FAILED")'
```

#### **A Note on Safety: Parallel vs. Sequential Execution**

The `--parallel` (`-P`) flag is powerful but potentially dangerous. Running an operation on all nodes at once can lead to a cluster-wide outage if used incorrectly.

*   **Commands that are generally SAFE for parallel execution:**
    *   `cass-ops health`
    *   `cass-ops cluster-health`
    *   `cass-ops disk-health`
    *   `cass-ops backup-status`
    *   `cass-ops repair` (though consider DC-by-DC or batching for large clusters)
    *   `cass-ops cleanup`

*   **Commands that should almost ALWAYS be run SEQUENTIALLY (without `-P`):**
    *   `cass-ops restart`
    *   `cass-ops reboot`
    *   `cass-ops decommission`
    *   `cass-ops upgrade-sstables`
    *   Any command that takes a node out of the gossip ring or stops the service.

Always use `--dry-run` first if you are unsure.
```bash
# Always a good idea before a destructive operation!
./scripts/cassy.sh --qv-query "-r role_cassandra_pfpt" --dry-run -c "sudo cass-ops decommission"
```
For all options, run the script with the `--help` flag:
```bash
./scripts/cassy.sh --help
```
