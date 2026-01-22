# `profile_cassandra_pfpt`: A Complete Cassandra Operations Profile

> This module provides a complete profile for deploying and managing an Apache Cassandra node. It acts as a wrapper around the `cassandra_pfpt` component module, providing all of its configuration data via Hiera lookups. This allows for a clean separation of logic from data.
>
> Beyond initial deployment, this profile equips each node with a powerful suite of automation and command-line tools to simplify and safeguard common operational tasks, from health checks and backups to complex disaster recovery scenarios.

---

## Table of Contents

1.  [Description](#description)
2.  [Setup](#setup)
3.  [Usage Examples](#usage-examples)
4.  [Operator's Quick Reference: Management Scripts](#operators-quick-reference-management-scripts)
5.  [Day-2 Operations Guide](#day-2-operations-guide)
    1.  [Node and Cluster Health Checks](#node-and-cluster-health-checks)
    2.  [Node Lifecycle Management](#node-lifecycle-management)
    3.  [Data and Maintenance Operations](#data-and-maintenance-operations)
6.  [Automated Maintenance Guide](#automated-maintenance-guide)
    1.  [Automated Backups](#automated-backups)
    2.  [Automated Repair](#automated-repair)
7.  [Disaster Recovery Guide: Point-in-Time Recovery](#disaster-recovery-guide-point-in-time-recovery)
    1.  [Restore Modes](#restore-modes)
    2.  [Example: Granular Table Restore](#example-granular-table-restore)
    3.  [Example: Full Cluster Restore (Cold Start)](#example-full-cluster-restore-cold-start)
8.  [Hiera Parameter Reference](#hiera-parameter-reference)
9.  [Puppet Agent Management](#puppet-agent-management)

---

## Description

This profile includes the `cassandra_pfpt` component module and provides it with a rich set of operational capabilities through Hiera-driven configuration and a suite of robust management scripts installed in `/usr/local/bin`. These scripts are your primary interface for safely managing the Cassandra cluster.

## Setup

This profile is intended to be included by a role class.

```puppet
# In your role manifest (e.g., roles/manifests/cassandra.pp)
class role::cassandra {
  include profile_cassandra_pfpt
}
```

> All configuration for the node should be provided via your Hiera data source (e.g., in your `common.yaml` or node-specific YAML files). The backup scripts require the `jq`, `awscli`, and `openssl` packages, which this profile will install by default.

---

## Usage Examples

### Comprehensive Configuration Example

The following Hiera example demonstrates how to configure a multi-node cluster with automated backups, scheduled repairs, and custom JVM settings enabled.

```yaml
# In your Hiera data (e.g., nodes/cassandra-node-1.yaml)

# --- Core Settings ---
profile_cassandra_pfpt::cluster_name: 'MyProductionCluster'
profile_cassandra_pfpt::cassandra_password: 'a-very-secure-password'

# --- Topology & Seeds ---
profile_cassandra_pfpt::datacenter: 'dc1'
profile_cassandra_pfpt::rack: 'rack1'
profile_cassandra_pfpt::seeds:
  - '10.0.1.10'
  - '10.0.1.11'
  - '10.0.1.12'

# --- JVM Settings ---
profile_cassandra_pfpt::max_heap_size: '8G'
profile_cassandra_pfpt::jvm_additional_opts:
  'print_flame_graphs': '-XX:+PreserveFramePointer'

# --- Backup Configuration ---
profile_cassandra_pfpt::backup_encryption_key: 'Your-Super-Secret-32-Character-Key' # IMPORTANT: Use Hiera-eyaml for this in production
profile_cassandra_pfpt::manage_full_backups: true
profile_cassandra_pfpt::full_backup_schedule: 'daily' # systemd timer spec
profile_cassandra_pfpt::manage_incremental_backups: true
profile_cassandra_pfpt::incremental_backup_schedule: '0 */4 * * *' # cron spec
profile_cassandra_pfpt::backup_s3_bucket: 'my-prod-cassandra-backups'
profile_cassandra_pfpt::clearsnapshot_keep_days: 7
profile_cassandra_pfpt::upload_streaming: false # Set to true to use faster but less-robust streaming uploads

# --- Automated Repair Configuration ---
profile_cassandra_pfpt::manage_scheduled_repair: true
profile_cassandra_pfpt::repair_schedule: '*-*-1/5 01:00:00' # Every 5 days
```

### Managing Cassandra Roles

You can declaratively manage Cassandra user roles. For production environments, it is highly recommended to encrypt passwords using **Hiera-eyaml**. The profile supports this automatically, as Puppet will decrypt the secrets before passing them to the module.

Here is an example showing both a plain-text password and an encrypted one:

```yaml
# In your Hiera data
profile_cassandra_pfpt::cassandra_roles:
  # Example with a plain-text password (suitable for development)
  'readonly_user':
    password: 'SafePassword123'
    is_superuser: false
    can_login: true

  # Example with a securely encrypted password using eyaml (for production)
  'app_admin':
    password: >
      ENC[PKCS7,MIIBojANBgkqhkiG9w0BAQEFAAOCAY8AMIIBigKCAYEAq3s4/L5W
      ... (rest of your encrypted string) ...
      9y9gBFdCIg4a5A==]
    is_superuser: true
    can_login: true
```

---

## Operator's Quick Reference: Management Scripts

This profile installs a suite of robust management scripts in `/usr/local/bin` on every Cassandra node. These are your primary tools for safe, manual operations.

| Script Name                    | Purpose                                                                                                     |
| ------------------------------ | ----------------------------------------------------------------------------------------------------------- |
| `node_health_check.sh`         | Performs a comprehensive health check of the local node (disk, status, gossip, logs).                       |
| `cluster-health.sh`            | Quickly verifies `nodetool status`, `cqlsh` connectivity, and the native transport port.                       |
| `disk-health-check.sh`         | Checks available disk space against warning/critical thresholds. Used by other scripts.                     |
| `version-check.sh`             | Audits and prints the versions of key software (OS, Java, Cassandra, Puppet).                               |
| `rolling_restart.sh`           | Safely performs a rolling restart of the Cassandra service on the local node (drain, stop, start, verify).  |
| `decommission-node.sh`         | Securely decommissions the local node, streaming its data to other replicas.                                |
| `prepare-replacement.sh`       | Configures a **new, stopped** node to replace a dead node in the cluster by setting the correct JVM flag.   |
| `rebuild-node.sh`              | Rebuilds the data on a node by streaming from another data center. Used for adding a node to a new DC.       |
| `range-repair.sh`              | **(Primary Repair Tool)** Initiates a safe, granular, low-impact repair of the node's data.                  |
| `compaction-manager.sh`        | Safely runs `nodetool compact` while monitoring disk space to prevent failures.                               |
| `garbage-collect.sh`           | Safely runs `nodetool garbagecollect` with pre-flight safety checks.                                      |
| `cleanup-node.sh`              | Safely runs `nodetool cleanup` after a new node is added to the cluster.                                    |
| `upgrade-sstables.sh`          | Safely runs `nodetool upgradesstables` after a major Cassandra version upgrade.                               |
| `restore-from-s3.sh`           | **(Primary Restore Tool)** A powerful script to restore data to a point in time from S3 backups.              |
| `full-backup-to-s3.sh`         | (Automated) Script executed by `systemd` to perform scheduled full backups.                                 |
| `incremental-backup-to-s3.sh`  | (Automated) Script executed by `systemd` to perform scheduled incremental backups.                          |
| `cassandra-upgrade-precheck.sh`| A detailed, non-invasive script to validate readiness for a major version upgrade (e.g., 3.11 to 4.0).         |
| `robust_backup.sh`             | Deprecated. Use `full-backup-to-s3.sh` with `backup_backend: 'local'`.                                     |

---

## Day-2 Operations Guide

This section provides a practical guide for common operational tasks.

### Node and Cluster Health Checks

> Before performing any maintenance, always check the health of the node and cluster.

*   **Check the Local Node:** Run `sudo /usr/local/bin/node_health_check.sh`. This script is your first stop. It checks disk space, node status (UN), gossip state, active streams, and recent log exceptions, giving you a quick "go/no-go" for maintenance.
*   **Check Cluster Connectivity:** Run `sudo /usr/local/bin/cluster-health.sh`. This verifies that the node can communicate with the cluster and that the CQL port is open.
*   **Check Disk Space Manually:** Run `sudo /usr/local/bin/disk-health-check.sh` to see the current free space percentage on the data volume.

### Node Lifecycle Management

#### Performing a Safe Rolling Restart
To apply configuration changes or for other maintenance, always use the provided script for a safe restart.

1.  SSH into the node you wish to restart.
2.  Execute `sudo /usr/local/bin/rolling_restart.sh`.
3.  The script will automatically drain the node, stop the service, start it again, and wait until it verifies the node has successfully rejoined the cluster in `UN` state.

#### Decommissioning a Node
When you need to permanently remove a node from the cluster:

1.  SSH into the node you want to remove.
2.  Run `sudo /usr/local/bin/decommission-node.sh`.
3.  The script will ask for confirmation, then run `nodetool decommission`. After it completes successfully, it is safe to shut down and terminate the instance.

#### Replacing a Failed Node
If a node has failed permanently and cannot be recovered, you must replace it with a new one.

1.  Provision a new machine with the same resources and apply this Puppet profile. **Do not start the Cassandra service.**
2.  SSH into the **new, stopped** node.
3.  Execute the `prepare-replacement.sh` script, providing the IP of the dead node it is replacing:
    ```bash
    sudo /usr/local/bin/prepare-replacement.sh <ip_of_dead_node>
    ```
4.  The script will configure the necessary JVM flag (`-Dcassandra.replace_address_first_boot`).
5.  You can now **start the Cassandra service** on the new node. It will automatically bootstrap into the cluster, assuming the identity and token ranges of the dead node.

### Data and Maintenance Operations

#### Repairing Data (`range-repair.sh`)
This is the primary script for running manual repairs. It intelligently breaks the repair into small token ranges to minimize performance impact.

*   **To repair all keyspaces (most common):**
    ```bash
    sudo /usr/local/bin/range-repair.sh
    ```
*   **To repair a specific keyspace:**
    ```bash
    sudo /usr/local/bin/range-repair.sh my_keyspace
    ```
> Run this sequentially on each node in the cluster for a full, safe, rolling repair.

#### Compaction (`compaction-manager.sh`)
To manually trigger compaction while safely monitoring disk space:

```bash
# Compact a specific table
sudo /usr/local/bin/compaction-manager.sh -k my_keyspace -t my_table

# Compact an entire keyspace
sudo /usr/local/bin/compaction-manager.sh -k my_keyspace
```

#### Garbage Collection (`garbage-collect.sh`)
To manually remove droppable tombstones with pre-flight safety checks:

```bash
sudo /usr/local/bin/garbage-collect.sh -k my_keyspace -t users
```

#### SSTable Upgrades (`upgrade-sstables.sh`)
After a major Cassandra version upgrade, run this on each node sequentially:

```bash
sudo /usr/local/bin/upgrade-sstables.sh
```

#### Node Cleanup (`cleanup-node.sh`)
After adding a new node to the cluster, run `cleanup` on the existing nodes in the same DC to remove data that no longer belongs to them.

```bash
sudo /usr/local/bin/cleanup-node.sh
```

---

## Automated Maintenance Guide

### Automated Backups

This profile provides a fully automated, S3-based backup solution using `systemd` timers.

#### How It Works
1.  **Granular Backups:** Backups are no longer single, large archives. Instead, each table (for full backups) or set of incremental changes is archived and uploaded as a small, separate file to S3.
2.  **Scheduling:** Puppet creates `systemd` timer units (`cassandra-full-backup.timer`, `cassandra-incremental-backup.timer`) on each node.
3.  **Execution:** `systemd` automatically triggers the backup scripts (`full-backup-to-s3.sh`, `incremental-backup-to-s3.sh`).
4.  **Process:** The scripts generate a `backup_manifest.json` with critical metadata for each backup run (identified by a `YYYY-MM-DD-HH-MM` timestamp), encrypt the archives, and upload them to a structured path in S3.
5.  **Local Snapshot Cleanup:** The full backup script automatically deletes local snapshots older than `clearsnapshot_keep_days`.

#### Pausing Backups
> To temporarily disable backups on a node for maintenance, create a flag file:
> `sudo touch /var/lib/backup-disabled`.
> To re-enable, simply remove the file.

### Automated Repair

A safe, low-impact, automated repair process is critical for data consistency.

#### How it Works
1.  **Configuration:** Enable via `profile_cassandra_pfpt::manage_scheduled_repair: true`.
2.  **Scheduling:** Puppet creates a `systemd` timer (`cassandra-repair.timer`) that, by default, runs every 5 days to align with a 10-day `gc_grace_seconds`.
3.  **Execution:** The timer runs the `range-repair.sh` script, which executes the intelligent Python script to repair the node in small, manageable chunks, minimizing performance impact.
4.  **Control:** You can manually stop, start, or check the status of a repair using `systemd` commands:
    *   `sudo systemctl stop cassandra-repair.service` (To kill a running repair)
    *   `sudo systemctl start cassandra-repair.service` (To manually start a repair)
    *   `sudo systemctl stop cassandra-repair.timer` (To pause the automated schedule)

---

## Disaster Recovery Guide: Point-in-Time Recovery

The `/usr/local/bin/restore-from-s3.sh` script is a powerful tool designed to restore data to a specific point in time by intelligently combining full and incremental backups.

### The Restore Process

1.  **Find the Backup Chain:** You provide a target timestamp. The script finds the most recent full backup *before* your target time, and all incremental backups between the full backup and your target.
2.  **Confirm:** It presents this "restore chain" to you for confirmation before proceeding.
3.  **Restore:** It restores the full backup, then applies each incremental backup in chronological order.

### Restore Modes

#### Mode 1: Granular Restore (Non-Destructive)
> This is the most common use case. It streams data for a specific table or keyspace into a **live, running cluster** without downtime.

*   **Usage:**
    ```bash
    # Restore a single table to its state at or before the target time
    # This will download the data and load it with sstableloader.
    sudo /usr/local/bin/restore-from-s3.sh --date "2026-01-20-18-00" --keyspace my_app --table users --download-and-restore

    # Or just download the data for manual inspection
    sudo /usr/local/bin/restore-from-s3.sh --date "2026-01-20-18-00" --keyspace my_app --download-only
    ```

#### Mode 2: Full Node Restore (Destructive)
> **WARNING:** This mode is for recovering a completely failed node. It will **WIPE ALL CASSANDRA DATA** on the target node before restoring.

*   **Usage:**
    ```bash
    # Restore the entire node to the state at the target time
    sudo /usr/local/bin/restore-from-s3.sh --date "2026-01-20-18-00" --full-restore
    ```

#### Mode 3: Schema-Only Restore
> This extracts the `schema.cql` file from the relevant full backup, which is the first step for a full cluster disaster recovery.

*   **Usage:**
    ```bash
    sudo /usr/local/bin/restore-from-s3.sh --date "2026-01-20-18-00" --schema-only
    ```
This saves the schema to `/tmp/schema_restore.cql`, which you can then apply to your new cluster using `cqlsh`.

### Example: Full Cluster Restore (Cold Start)

This procedure restores a full cluster from S3 backups onto brand-new machines where the schema does not exist.

> #### Prerequisites
> *   You have full and incremental backups for each node of the old cluster in S3.
> *   You have provisioned new machines, applied this Puppet profile, and the `cassandra` service is **stopped** on all of them.

#### Step 1: Restore the Schema
1.  Choose **one node** in the new cluster. Start the `cassandra` service on this node only.
2.  SSH into that node.
3.  Choose a target restore time and run the script in schema-only mode:
    ```bash
    sudo /usr/local/bin/restore-from-s3.sh --date "YYYY-MM-DD-HH-MM" --schema-only
    ```
4.  The script will download `/tmp/schema_restore.cql`. Apply it to the new cluster:
    ```bash
    cqlsh -u cassandra -p 'YourPassword' --ssl -f /tmp/schema_restore.cql
    ```
5.  Stop the `cassandra` service on this node. The entire new cluster should now be offline.

#### Step 2: Perform a Rolling Restore of All Nodes
The restore script handles the complexity of determining whether to start as a first seed or join an existing cluster.

1.  **On each node (one at a time):**
    *   SSH into the new node.
    *   Run the restore script in full mode with the desired point-in-time timestamp.
        ```bash
        sudo /usr/local/bin/restore-from-s3.sh --date "YYYY-MM-DD-HH-MM" --full-restore
        ```
    *   The script will download and apply the full backup and all necessary incrementals. It will then start Cassandra.
    *   Wait for the node to come online and report `UN` in `nodetool status` before moving to the next node.

2.  Repeat for all remaining nodes until the entire new cluster is recovered.

---

## Hiera Parameter Reference

This section documents every available Hiera key for this profile.

### Core Settings
*   `profile_cassandra_pfpt::cassandra_version` (String): The version of the Cassandra package to install. Default: `'4.1.10-1'`.
*   `profile_cassandra_pfpt::java_version` (String): The major version of Java to install (e.g., '8', '11'). Default: `'11'`.
*   `profile_cassandra_pfpt::cluster_name` (String): The name of the Cassandra cluster. Default: `'pfpt-cassandra-cluster'`.
*   `profile_cassandra_pfpt::seeds` (Array[String]): A list of seed node IP addresses. If empty, the node will seed from itself. Default: `[]`.
*   `profile_cassandra_pfpt::cassandra_password` (String): The password for the main `cassandra` superuser. Default: `'PP#C@ss@ndr@000'`.

### Topology
*   `profile_cassandra_pfpt::datacenter` (String): The name of the datacenter this node belongs to. Default: `'dc1'`.
*   `profile_cassandra_pfpt::rack` (String): The name of the rack this node belongs to. Default: `'rack1'`.
*   `profile_cassandra_pfpt::endpoint_snitch` (String): The snitch to use for determining network topology. Default: `'GossipingPropertyFileSnitch'`.
*   `profile_cassandra_pfpt::racks` (Hash): A hash for mapping racks to datacenters, used by `GossipingPropertyFileSnitch`. Default: `{}`.

### Networking
*   `profile_cassandra_pfpt::listen_address` (String): The IP address for Cassandra to listen on. Default: `$facts['networking']['ip']`.
*   `profile_cassandra_pfpt::native_transport_port` (Integer): The port for CQL clients. Default: `9042`.
*   `profile_cassandra_pfpt::storage_port` (Integer): The port for internode communication. Default: `7000`.
*   `profile_cassandra_pfpt::ssl_storage_port` (Integer): The port for SSL internode communication. Default: `7001`.
*   `profile_cassandra_pfpt::rpc_port` (Integer): The port for the Thrift RPC service. Default: `9160`.
*   `profile_cassandra_pfpt::start_native_transport` (Boolean): Whether to start the CQL native transport service. Default: `true`.
*   `profile_cassandra_pfpt::start_rpc` (Boolean): Whether to start the legacy Thrift RPC service. Default: `true`.

### Directories & Paths
*   `profile_cassandra_pfpt::data_dir` (String): Path to the data directories. Default: `'/var/lib/cassandra/data'`.
*   `profile_cassandra_pfpt::commitlog_dir` (String): Path to the commit log directory. Default: `'/var/lib/cassandra/commitlog'`.
*   `profile_cassandra_pfpt::saved_caches_dir` (String): Path to the saved caches directory. Default: `'/var/lib/cassandra/saved_caches'`.
*   `profile_cassandra_pfpt::hints_directory` (String): Path to the hints directory. Default: `'/var/lib/cassandra/hints'`.
*   `profile_cassandra_pfpt::cdc_raw_directory` (String): Path for Change Data Capture logs. Default: `'/var/lib/cassandra/cdc_raw'`.

### JVM & Performance
*   `profile_cassandra_pfpt::max_heap_size` (String): The maximum JVM heap size (e.g., '4G', '8000M'). Default: `'3G'`.
*   `profile_cassandra_pfpt::gc_type` (String): The garbage collector type to use ('G1GC' or 'CMS'). Default: `'G1GC'`.
*   `profile_cassandra_pfpt::num_tokens` (Integer): The number of tokens to assign to the node. Default: `256`.
*   `profile_cassandra_pfpt::initial_token` (String): For disaster recovery, specifies the comma-separated list of tokens for the first node being restored in a new cluster. Should be used with `num_tokens: 1`. Default: `undef`.
*   `profile_cassandra_pfpt::concurrent_reads` (Integer): The number of concurrent read requests. Default: `32`.
*   `profile_cassandra_pfpt::concurrent_writes` (Integer): The number of concurrent write requests. Default: `32`.
*   `profile_cassandra_pfpt::concurrent_compactors` (Integer): The number of concurrent compaction processes. Default: `4`.
*   `profile_cassandra_pfpt::compaction_throughput_mb_per_sec` (Integer): Throttles compaction to a specific throughput. Default: `16`.
*   `profile_cassandra_pfpt::jvm_additional_opts` (Hash): A hash of extra JVM arguments to add or override in `jvm-server.options`. Default: `{}`.

### Security & Authentication
*   `profile_cassandra_pfpt::authenticator` (String): The authentication backend. Default: `'PasswordAuthenticator'`.
*   `profile_cassandra_pfpt::authorizer` (String): The authorization backend. Default: `'CassandraAuthorizer'`.
*   `profile_cassandra_pfpt::role_manager` (String): The role management backend. Default: `'CassandraRoleManager'`.
*   `profile_cassandra_pfpt::cassandra_roles` (Hash): A hash defining user roles to be managed declaratively. See example above. Default: `{}`.
*   `profile_cassandra_pfpt::system_keyspaces_replication` (Hash): Defines the replication factor for system keyspaces in a multi-DC setup. Example: `{ 'dc1' => 3, 'dc2' => 3 }`. Default: `{}`.

### Automated Maintenance
*   `profile_cassandra_pfpt::manage_scheduled_repair` (Boolean): Set to `true` to enable the automated weekly repair job. Default: `false`.
*   `profile_cassandra_pfpt::repair_schedule` (String): The `systemd` OnCalendar schedule for the automated repair job. Default: `'*-*-1/5 01:00:00'`. This schedules the repair to run every 5 days, which is a safe interval for a 10-day `gc_grace_seconds`.
*   `profile_cassandra_pfpt::repair_keyspace` (String): If set, the automated repair job will only repair this specific keyspace. If unset, it repairs all non-system keyspaces. Default: `undef`.
*   `profile_cassandra_pfpt::manage_full_backups` (Boolean): Enables the scheduled full backup script. Default: `false`.
*   `profile_cassandra_pfpt::manage_incremental_backups` (Boolean): Enables the scheduled incremental backup script. Default: `false`.
*   `profile_cassandra_pfpt::backup_encryption_key` (Sensitive[String]): The secret key used to encrypt all backup archives. **WARNING:** This has an insecure default value to prevent Puppet runs from failing. You **MUST** override this with a strong, unique secret in your production Hiera data. Default: `'MustBeChanged-ChangeMe-ChangeMe!!'`.
*   `profile_cassandra_pfpt::backup_backend` (String): The storage backend to use for uploads. Set to `'local'` to disable uploads. Default: `'s3'`.
*   `profile_cassandra_pfpt::backup_s3_bucket` (String): The name of the S3 bucket to use when `backup_backend` is `'s3'`. Default: `'puppet-cassandra-backups'`.
*   `profile_cassandra_pfpt::clearsnapshot_keep_days` (Integer): The number of days to keep local snapshots on the node before they are automatically deleted. Set to 0 to disable. Default: `3`.
*   `profile_cassandra_pfpt::upload_streaming` (Boolean): Whether to use a direct streaming pipeline for backups (`true`) or a more robust method using temporary files (`false`). Streaming is faster but can hide errors. Default: `false`.

---

## Puppet Agent Management

The base `cassandra_pfpt` component module includes logic to manage the Puppet agent itself by ensuring a scheduled run is in place via cron.

*   **Scheduled Runs:** By default, the Puppet agent will run twice per hour at a staggered minute.
*   **Maintenance Window:** The cron job will **not** run if a file exists at `/var/lib/puppet-disabled`. Creating this file is the standard way to temporarily disable Puppet runs.
*   **Configuration:** You can override the default schedule by setting the `profile_cassandra_pfpt::puppet_cron_schedule` key in Hiera to a standard 5-field cron string.
