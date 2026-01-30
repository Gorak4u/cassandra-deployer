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
| `-P`, `--parallel` | `[N]` | Execute in parallel. Uses a worker pool model with a concurrency of N. Defaults to all nodes at once if N is omitted. |
| `--ssh-options` | `<opts>` | Quoted string of additional options for the SSH command (e.g., "-i /path/key.pem"). |
| `--dry-run` | | Show which nodes would be targeted and what command would run, without executing. |
| `-i`, `--interactive` | | Prompt for confirmation before executing on target nodes. |
| `--json` | | Output results in a machine-readable JSON format. |
| `--timeout` | `<seconds>` | Set a timeout in seconds for the command on each node. `0` for no timeout. |
| `--output-dir`| `<path>` | Save the output from each node to a separate file in the specified directory. |
| `--retries` | `<N>` | Number of times to retry a failed command on a node. Default: 0. |
| `--rolling-op` | `<type>` | Perform a predefined safe rolling operation: 'restart', 'reboot', or 'puppet'. This is a shortcut that enforces sequential execution and an inter-node health check. |
| `--pre-exec-check` | `<path>` | A local script to run before executing. If it fails, cassy.sh aborts. |
| `--post-exec-check`| `<path>` | A local script to run after executing on all nodes. |
| `--inter-node-check`| `<path>` | In sequential mode, a local script to run after each node. If it fails, the rolling execution stops. |
| `-h`, `--help` | | Show the help message. |


### Production Cassandra Operations with `cassy.sh`

This section provides recipes for common, production-level Cassandra maintenance tasks using `cassy.sh`.

#### **Pattern 1: Safe Rolling Restart of a Datacenter**
A rolling restart is a common maintenance task. It must be done sequentially to ensure the cluster remains available. The `--inter-node-check` flag is critical for ensuring the cluster is healthy before moving to the next node.

First, create a simple health check script, for example `check_cluster.sh`:
```bash
#!/bin/bash
# check_cluster.sh
echo "Running health check against cluster..."
# Use cassy.sh to run a health check on a *single* known-good node.
# If this fails, the whole rolling restart will stop.
./scripts/cassy.sh --node cassandra-seed-1.example.com -c "sudo cass-ops cluster-health --silent"
```
*Make sure this script is executable (`chmod +x check_cluster.sh`)*.

Now, use it in your rolling restart command:
```bash
# Restart all Cassandra nodes in the AWSLAB datacenter, one by one,
# running a health check after each node restart.
./scripts/cassy.sh --qv-query "-r role_cassandra_pfpt -d AWSLAB" \
  -c "sudo cass-ops restart" \
  --inter-node-check ./check_cluster.sh
```

#### **Pattern 2: Parallel Cluster-Wide Repair**
Unlike restarts, `nodetool repair` is safe to run in parallel across the cluster. For very large clusters, it's best practice to run it per-datacenter to control cross-datacenter network traffic. You can also use the managed parallel execution to limit the impact.

```bash
# Run repair on all Cassandra nodes in the SC4 datacenter simultaneously.
./scripts/cassy.sh --qv-query "-r role_cassandra_pfpt -d SC4" --parallel -c "sudo cass-ops repair"

# Run repair in batches of 5 nodes at a time, using the efficient worker pool model.
./scripts/cassy.sh --qv-query "-r role_cassandra_pfpt -d SC4" --parallel 5 -c "sudo cass-ops repair"
```

#### **Pattern 3: Programmatic Health Auditing**
You can use `cassy.sh` with the `--json` flag to programmatically audit your cluster's health and parse the results, which is ideal for automation.

```bash
# Get health status from all nodes and use jq to print the details of any failed checks.
./scripts/cassy.sh --qv-query "-r role_cassandra_pfpt" --json -c "sudo cass-ops health --json" | jq '.results[] | select(.status == "FAILED")'
```

#### **Pattern 4: Fully Automated Rolling Operations**
For the most critical operations, `cassy.sh` includes a powerful `--rolling-op` flag to handle safe, automated rolling operations. This is the recommended method for tasks like restarts, reboots, or Puppet runs.

This feature uses a master health check script (`scripts/check_cluster_health.sh`) which has built-in retry logic. It runs between each node operation to ensure the cluster remains stable. If the health check fails at any point, the entire rolling operation is halted to prevent cascading failures.

The `--rolling-op` flag takes one argument: the **operation** to perform.

**Available Operations:**
*   `restart`: Performs a safe rolling restart of the Cassandra service (`cass-ops restart`).
*   `reboot`: Performs a safe rolling reboot of the nodes (`cass-ops reboot`).
*   `puppet`: Performs a rolling Puppet agent run (`puppet agent -t`).

**Usage Example:**

To perform a safe rolling restart of all Cassandra nodes in the AWSLAB datacenter:
```bash
./scripts/cassy.sh --rolling-op restart --qv-query "-r role_cassandra_pfpt -d AWSLAB"
```

To perform a rolling Puppet run on the same set of nodes:
```bash
./scripts/cassy.sh --rolling-op puppet --qv-query "-r role_cassandra_pfpt -d AWSLAB"
```

This feature provides a single, robust way to orchestrate complex operations, node by node, with health checks at every step.

> **Note:** The older `rolling_restart.sh`, `rolling_reboot.sh`, and `rolling_puppet_run.sh` scripts are now simple wrappers around this new functionality for backward compatibility.

#### **Pattern 5: Joining Two Datacenters for Multi-DC Replication**

A common advanced scenario is joining a new, standalone Cassandra cluster (e.g., in a new region) to an existing one to form a single, multi-datacenter cluster. The project includes an orchestrator script, `scripts/join-cassandra-dcs.sh`, designed for this purpose.

This script uses `cassy.sh` as its engine to safely perform the required steps from a central management node.

**Prerequisites:**

1.  **Cluster Name Match:** Both clusters MUST have the exact same `cluster_name` in their `cassandra.yaml`.
2.  **Version Match:** Both clusters MUST be running the same major versions of Cassandra and Java.
3.  **Network Connectivity:** Firewall rules must be in place to allow bi-directional communication on the Cassandra storage ports (default 7000/7001) between **all nodes** in both datacenters.
4.  **Configuration Management:** Before running the script, your Puppet/Hiera configuration must be updated. Specifically, the `seeds` list in your `cassandra.yaml` for nodes in the *new* datacenter should be updated to include at least one seed from the *old* datacenter. This change should be applied via a rolling restart (`cassy.sh --rolling-op puppet`) before proceeding.

**Usage Example:**

The script requires `qv` queries to identify the nodes in each datacenter and the names of the datacenters as they are known to Cassandra.

```bash
./scripts/join-cassandra-dcs.sh \
  --old-dc-query "-r role_cassandra_pfpt -d us-east-1" \
  --new-dc-query "-r role_cassandra_pfpt -d eu-west-1" \
  --old-dc-name "us-east-1" \
  --new-dc-name "eu-west-1"
```

**What the script does:**

1.  **Validation:** Fetches node lists and validates that the cluster names match.
2.  **Alter Topology:** Connects to a node in the old datacenter and executes the necessary `ALTER KEYSPACE` commands on `system_auth` and `system_distributed` to make them aware of the new datacenter's replication factor.
3.  **Rolling Restart:** Performs a safe, rolling restart of all nodes in the **new** datacenter. This forces them to pick up the updated gossip information and see the nodes from the old datacenter.
4.  **Data Rebuild:** Executes `nodetool rebuild <old_dc_name>` sequentially on each node in the **new** datacenter. This is the final step, where data is streamed from the existing datacenter to populate the new one.

To see all options, run the script with the `--help` flag:
```bash
./scripts/join-cassandra-dcs.sh --help
```

#### **Pattern 6: Splitting a Multi-DC Cluster**

The reverse of joining datacenters is splitting them into two independent clusters. This is a complex and potentially destructive operation. The `scripts/split-cassandra-dcs.sh` script is designed to orchestrate this process safely.

**Prerequisites:**

1.  **Full Backup:** Before starting, ensure you have a complete, verified backup of all your data.
2.  **Network Isolation:** Plan for network rule changes that will eventually prevent communication between the two datacenters after the split is complete.

**Usage Example:**

```bash
./scripts/split-cassandra-dcs.sh \
  --dc1-query "-r role_cassandra_pfpt -d us-east-1" \
  --dc2-query "-r role_cassandra_pfpt -d eu-west-1" \
  --dc1-name "us-east-1" \
  --dc2-name "eu-west-1"
```

**What the script does:**

1.  **Isolates Topologies:** It alters the `system_auth` and `system_distributed` keyspaces on each datacenter to remove the other from its replication strategy.
2.  **Rolling Restarts:** It performs a safe rolling restart of each datacenter sequentially to ensure the new, isolated topologies are loaded.
3.  **Finalizes Split:** After the script finishes, you must apply firewall rules to block traffic between the two former datacenters. The clusters are now fully independent.

To see all options, run the script with the `--help` flag:
```bash
./scripts/split-cassandra-dcs.sh --help
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

*   **Commands that should almost ALWAYS be run SEQUENTIALLY (without `-P`), ideally with `--inter-node-check`:**
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

    