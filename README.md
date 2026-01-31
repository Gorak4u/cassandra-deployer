# Cassandra Orchestration Toolkit

This repository contains a suite of powerful orchestration tools designed to safely manage and operate Apache Cassandra clusters. The primary tool, `cassy.sh`, is a robust wrapper for executing commands across multiple nodes, supporting both sequential and parallel operations with built-in safety checks.

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

#### **A Note on Safety: Disabling Automation During Complex Operations**
For multi-step, stateful operations like joining, splitting, or renaming a cluster, it is critical to temporarily disable other automated processes (like Puppet runs or scheduled repairs) to prevent them from interfering.

The `cass-ops` tool provides a simple way to do this.

**Before starting a complex operation:**
Run the following command, targeting all nodes involved in the operation:
```bash
./scripts/cassy.sh --qv-query "<your_query>" -P -c "sudo cass-ops disable-automation 'Pausing for cluster maintenance'"
```

**After the operation is fully complete:**
Re-enable automation on all nodes:
```bash
./scripts/cassy.sh --qv-query "<your_query>" -P -c "sudo cass-ops enable-automation"
```
> **Note:** The `join-cassandra-dcs.sh`, `split-cassandra-dcs.sh`, and `rename-cassandra-cluster.sh` orchestration scripts perform the "disable" step automatically for you. However, they require you to **manually** run the "enable" command after you have verified the operation was successful.

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

> **Note:** The `rolling_restart.sh`, `rolling_reboot.sh`, and `rolling_puppet_run.sh` scripts are now simple wrappers around this new functionality for backward compatibility.

#### **Pattern 5: Joining Two Datacenters for Multi-DC Replication**

A common advanced scenario is joining a new, standalone Cassandra cluster (e.g., in a new region) to an existing one to form a single, multi-datacenter cluster. The project includes an orchestrator script, `scripts/join-cassandra-dcs.sh`, designed for this purpose.

This script uses `cassy.sh` as its engine to safely perform the required steps from a central management node.

> **Important Safety Note:** This script will automatically disable Puppet and other automation on all nodes in both datacenters before it begins. Once the process is complete, you **must manually re-enable automation** after verifying the cluster's health. The script will provide the exact commands to run.

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
2.  **Safety Lock:** Disables automation on all nodes in both datacenters.
3.  **Alter Topology:** Connects to a node in the old datacenter and executes the necessary `ALTER KEYSPACE` commands on `system_auth` and `system_distributed` to make them aware of the new datacenter's replication factor.
4.  **Rolling Restart:** Performs a safe, rolling restart of all nodes in the **new** datacenter. This forces them to pick up the updated gossip information and see the nodes from the old datacenter.
5.  **Data Rebuild:** Executes `nodetool rebuild <old_dc_name>` sequentially on each node in the **new** datacenter. This is the final step, where data is streamed from the existing datacenter to populate the new one.
6.  **Final Instructions:** The script concludes by reminding you to manually re-enable automation.

#### **Pattern 6: Splitting a Multi-DC Cluster**

The reverse of joining datacenters is splitting them into two independent clusters. This is a complex operation that should be performed with care. The `scripts/split-cassandra-dcs.sh` script is designed to orchestrate this process safely.

> **Important Safety Note:** This script will automatically disable Puppet and other automation on all nodes in both datacenters before it begins. Once the process is complete, you **must manually re-enable automation** after verifying each cluster is stable and independent. The script will provide the exact commands to run.

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

1.  **Safety Lock:** Disables automation on all nodes in both datacenters.
2.  **Isolates Topologies:** It alters the `system_auth` and `system_distributed` keyspaces on each datacenter to remove the other from its replication strategy.
3.  **Rolling Restarts:** It performs a safe rolling restart of each datacenter sequentially to ensure the new, isolated topologies are loaded.
4.  **Final Instructions:** After the script finishes, you must apply firewall rules to block traffic between the two former datacenters. The clusters are now fully independent. The script will also remind you to manually re-enable automation.

#### **Pattern 7: Renaming a Cluster (Downtime Required)**

Renaming a Cassandra cluster is a rare but critical operation that requires a full cluster shutdown. The `scripts/rename-cassandra-cluster.sh` orchestrator automates this high-risk procedure.

> **Important Safety Note:** This script will automatically disable Puppet and other automation on all nodes in the cluster before it begins. Once the process is complete, you **must manually re-enable automation** after verifying the cluster's health. The script will provide the exact command to run.

**Prerequisites:**

1.  **Downtime:** Schedule a maintenance window. This is **not** a zero-downtime operation.
2.  **Configuration Plan:** Know the old cluster name and the desired new name.

**Usage Example:**

```bash
./scripts/rename-cassandra-cluster.sh \
  --qv-query "-r role_cassandra_pfpt -d us-east-1" \
  --old-name "MyProductionCluster" \
  --new-name "MyPrimaryCluster"
```

**What the script does:**

1.  **Validation:** Confirms that the current cluster name matches the provided old name.
2.  **Safety Lock:** Disables automation on all nodes.
3.  **Live `system.local` Update:** While the cluster is still running, it updates the `system.local` table on all nodes with the new cluster name.
4.  **Full Shutdown:** It safely stops the `cassandra` service on all nodes in the cluster.
5.  **Config File Update:** It uses `sed` to update the `cluster_name` setting in `cassandra.yaml` on every node.
6.  **Full Start:** It issues a start command to all nodes.
7.  **Final Instructions:** After the script completes, you **must** update your Hiera configuration (`profile_cassandra_pfpt::cluster_name`) to match the new name to make the change permanent. The script will also remind you to manually re-enable automation.

#### **Pattern 8: Performing a Zero-Downtime Rolling Upgrade**

Upgrading Cassandra is a critical operation that must be done sequentially and with care. This procedure leverages Puppet as the source of truth for the target version and `cassy.sh` to orchestrate the rollout safely across the cluster.

**Prerequisites:**

*   Read the official Cassandra upgrade guide for the versions you are moving between. Pay close attention to any required configuration changes or pre-flight checks. The `cass-ops upgrade-check` command is a useful tool for this.

**Step 1: Update the Target Version in Hiera**

The first and most important step is to declare the new version in your configuration data. You should never upgrade packages manually; always let Puppet manage the versions.

In your Hiera data (e.g., `common.yaml`), update the `cassandra_version` key:

```yaml
# BEFORE
profile_cassandra_pfpt::cassandra_version: '4.0.10-1'

# AFTER
profile_cassandra_pfpt::cassandra_version: '4.1.3-1'
```

**Step 2: Orchestrate the Rolling Upgrade with Puppet**

Now, use `cassy.sh`'s `--rolling-op puppet` feature. This will run `puppet agent -t` on each node in your cluster, one by one. The built-in health check will run between each node, ensuring that the cluster remains healthy and available as the new version is rolled out.

```bash
# This command tells cassy.sh to run Puppet on every node in the datacenter,
# sequentially, with a full health check after each node finishes.
./scripts/cassy.sh --rolling-op puppet --qv-query "-r role_cassandra_pfpt -d AWSLAB"
```

Puppet will automatically handle stopping the service, upgrading the package via the package manager, and restarting the service.

**Step 3: Run `upgradesstables` on All Nodes**

After the package upgrade is complete on all nodes, the final step is to rewrite the on-disk data files (SSTables) to the new version's format. This operation is safe to run in parallel on all nodes.

```bash
# Run upgradesstables in parallel on all nodes in the datacenter.
./scripts/cassy.sh --qv-query "-r role_cassandra_pfpt -d AWSLAB" --parallel -c "sudo cass-ops upgradesstables"
```

Once this command completes, your upgrade is finished.

#### **A Note on Safety: Parallel vs. Sequential Execution**

The `--parallel` (`-P`) flag is powerful but potentially dangerous. Running an operation on all nodes at once can lead to a cluster-wide outage if used incorrectly.

*   **Commands that are generally SAFE for parallel execution:**
    *   `cass-ops health`
    *   `cass-ops cluster-health`
    *   `cass-ops disk-health`
    *   `cass-ops backup-status`
    *   `cass-ops repair` (though consider DC-by-DC or batching for large clusters)
    *   `cass-ops cleanup`
    *   `cass-ops upgradesstables`

*   **Commands that should almost ALWAYS be run SEQUENTIALLY (without `-P`), ideally with `--inter-node-check` or as a `--rolling-op`:**
    *   `cass-ops restart`
    *   `cass-ops reboot`
    *   `cass-ops decommission`
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

### Integrating with CI/CD (Jenkins)

The `cassy.sh` script is designed for automation and can be easily integrated into a Jenkins pipeline to create auditable, repeatable, and parameterized operational jobs.

#### **Prerequisites**

1.  **Dedicated Jenkins Agent**: Set up a Jenkins agent (node) that will be responsible for running cluster operations.
2.  **SSH Key Access**: The `jenkins` user on the agent machine must have a passwordless SSH key configured. The public key must be added to the `authorized_keys` file for the appropriate user on all Cassandra nodes.
3.  **Required Tools**: The Jenkins agent must have `bash`, `qv` (your inventory tool), and `jq` installed.
4.  **Jenkins Credentials Plugin**: Install the "SSH Agent" plugin in Jenkins to securely manage your SSH key. Store your private SSH key in the Jenkins credential store.

#### **Example 1: Generic `cass-ops` Job**

This parameterized pipeline allows an operator to run any `cass-ops` command against any set of nodes defined by a `qv` query.

**Jenkinsfile:**
```groovy
pipeline {
    agent { label 'cassandra-ops' } // Use your dedicated agent label

    parameters {
        string(name: 'QV_QUERY', defaultValue: '-r role_cassandra_pfpt -d AWSLAB', description: 'The qv query to select target nodes.')
        string(name: 'CASSY_COMMAND', defaultValue: 'sudo cass-ops health', description: 'The command to run on the nodes.')
        booleanParam(name: 'PARALLEL_EXECUTION', defaultValue: false, description: 'Run in parallel on all nodes?')
    }

    stages {
        stage('Checkout') {
            steps {
                git 'https://your-git-server/your-repo.git'
            }
        }

        stage('Execute Operation') {
            steps {
                sshagent(credentials: ['your-jenkins-ssh-key-id']) {
                    script {
                        def parallel_flag = params.PARALLEL_EXECUTION ? '--parallel' : ''
                        
                        sh """
                            ./scripts/cassy.sh --qv-query "${params.QV_QUERY}" \
                               -c "${params.CASSY_COMMAND}" \
                               ${parallel_flag}
                        """
                    }
                }
            }
        }
    }
}
```

#### **Example 2: Safe Rolling Restart Job**

This pipeline provides a one-click job for the most common safe operation: a rolling restart.

**Jenkinsfile:**
```groovy
pipeline {
    agent { label 'cassandra-ops' }

    parameters {
        string(name: 'DATACENTER', defaultValue: 'AWSLAB', description: 'The datacenter to perform the rolling restart on.')
    }

    stages {
        stage('Checkout') {
            steps {
                git 'https://your-git-server/your-repo.git'
            }
        }

        stage('Execute Rolling Restart') {
            steps {
                sshagent(credentials: ['your-jenkins-ssh-key-id']) {
                    sh """
                        ./scripts/cassy.sh --rolling-op restart --qv-query "-r role_cassandra_pfpt -d ${params.DATACENTER}"
                    """
                }
            }
        }
    }
    
    post {
        always {
            echo 'Rolling restart job finished.'
            // Add notifications (Slack, Email, etc.) here
        }
    }
}
```

By creating Jenkins jobs like these, you empower your operations team to perform complex tasks safely without needing direct shell access to the management node, providing a clear audit trail for every action taken.
