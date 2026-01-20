# `profile_cassandra_pfpt`

## Table of Contents

1.  [Description](#description)
2.  [Setup](#setup)
3.  [Usage Examples](#usage-examples)
4.  [Hiera Parameter Reference](#hiera-parameter-reference)
5.  [Puppet Agent Management](#puppet-agent-management)
6.  [Backup and Restore](#backup-and-restore)
    1.  [Automated Backups](#automated-backups)
    2.  [Restoring from a Backup](#restoring-from-a-backup)
    3.  [Disaster Recovery: Restoring to a Brand New Cluster (Cold Start)](#disaster-recovery-restoring-to-a-brand-new-cluster-cold-start)
7.  [Compaction Management](#compaction-management)
8.  [Garbage Collection](#garbage-collection)
9.  [SSTable Upgrades](#sstable-upgrades)
10. [Node Cleanup](#node-cleanup)
11. [Limitations](#limitations)
12. [Development](#development)
## Description

This module provides a complete profile for deploying and managing an Apache Cassandra node. It acts as a wrapper around the `cassandra_pfpt` component module, providing all of its configuration data via Hiera lookups. This allows for a clean separation of logic (in the component module) from data (in Hiera).
## Setup

This profile is intended to be included by a role class. For example:

```puppet
# In your role manifest (e.g., roles/manifests/cassandra.pp)
class role::cassandra {
  include profile_cassandra_pfpt
}
```

All configuration for the node should be provided via your Hiera data source (e.g., in your `common.yaml` or node-specific YAML files). The backup scripts require the `jq` and `awscli` packages, which this profile will install by default.
## Usage Examples

### Comprehensive Configuration Example

The following Hiera example demonstrates how to configure a multi-node cluster with backups and custom JVM settings enabled.

```yaml
# In your Hiera data (e.g., nodes/cassandra-node-1.yaml)

# --- Core Settings ---
profile_cassandra_pfpt::cluster_name: 'MyProductionCluster'
profile_cassandra_pfpt::cassandra_password: 'a-very-secure-password'

# --- Topology & Seeds ---
profile_cassandra_pfpt::datacenter: 'dc1'
profile_cassandra_pfpt::rack: 'rack1'
profile_cassandra_pfpt::seeds: # Use 'seeds' not 'seeds_list'
  - '10.0.1.10'
  - '10.0.1.11'
  - '10.0.1.12'

# --- JVM Settings ---
profile_cassandra_pfpt::max_heap_size: '8G' # Set max heap to 8 Gigabytes
profile_cassandra_pfpt::jvm_additional_opts: # Use 'jvm_additional_opts' not 'extra_jvm_args_override'
  'print_flame_graphs': '-XX:+PreserveFramePointer'

# --- Backup Configuration ---
# Enable Cassandra's internal mechanism for creating incremental backup files
profile_cassandra_pfpt::incremental_backups: true

# Enable the full backup process via Puppet
profile_cassandra_pfpt::manage_full_backups: true
profile_cassandra_pfpt::full_backup_schedule: 'daily' # Runs at midnight

# Enable the incremental backup process via Puppet
profile_cassandra_pfpt::manage_incremental_backups: true
profile_cassandra_pfpt::incremental_backup_schedule: '0 */4 * * *' # Runs every 4 hours

# Define the S3 bucket for all backups
profile_cassandra_pfpt::backup_s3_bucket: 'my-prod-cassandra-backups'

# --- Enable streaming for full backups to save local disk space ---
profile_cassandra_pfpt::backup_upload_streaming: true

# --- Set local snapshot retention ---
profile_cassandra_pfpt::clearsnapshot_keep_days: 7 # Use 'clearsnapshot_keep_days'
```

### Managing Cassandra Roles

You can declaratively manage Cassandra user roles.

```yaml
profile_cassandra_pfpt::cassandra_roles:
  'readonly_user':
    password: 'SafePassword123'
    is_superuser: false
    can_login: true
  'app_admin':
    password: 'AnotherSafePassword456'
    is_superuser: true
    can_login: true
```
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

### TLS/SSL Encryption

*   `profile_cassandra_pfpt::ssl_enabled` (Boolean): Master switch to enable TLS/SSL encryption. Default: `false`.
*   `profile_cassandra_pfpt::keystore_password` (String): Password for the keystore. Default: `'ChangeMe'`.
*   `profile_cassandra_pfpt::truststore_password` (String): Password for the truststore. Default: `'changeit'`.
*   `profile_cassandra_pfpt::internode_encryption` (String): Encryption mode for server-to-server communication (`all`, `none`, `dc`, `rack`). Default: `'all'`.
*   Additional TLS parameters are available; see `profile_cassandra_pfpt/manifests/init.pp` for the full list.

### System & OS Tuning

*   `profile_cassandra_pfpt::disable_swap` (Boolean): If true, will disable swap and comment it out in `/etc/fstab`. Default: `true`.
*   `profile_cassandra_pfpt::sysctl_settings` (Hash): A hash of kernel parameters to set in `/etc/sysctl.d/99-cassandra.conf`. Default: `{ 'fs.aio-max-nr' => 1048576 }`.
*   `profile_cassandra_pfpt::limits_settings` (Hash): A hash of user limits to set in `/etc/security/limits.d/cassandra.conf`. Default: `{ 'memlock' => 'unlimited', 'nofile' => 100000, ... }`.

### Package Management

*   `profile_cassandra_pfpt::manage_repo` (Boolean): Whether Puppet should manage the Cassandra YUM repository. Default: `true`.
*   `profile_cassandra_pfpt::package_dependencies` (Array[String]): An array of dependency packages to install. Default: `['cyrus-sasl-plain', 'jemalloc', 'python3', 'numactl', 'jq', 'awscli']`.

### Backup and Restore

*   `profile_cassandra_pfpt::manage_full_backups` (Boolean): Enables the scheduled full backup script. Default: `false`.
*   `profile_cassandra_pfpt::manage_incremental_backups` (Boolean): Enables the scheduled incremental backup script. Default: `false`.
*   `profile_cassandra_pfpt::backup_backend` (String): The storage backend to use for uploads. Currently only supports `'s3'`. If set to another value, backups will be created locally but not uploaded. Default: `'s3'`.
*   `profile_cassandra_pfpt::backup_s3_bucket` (String): The name of the S3 bucket to use when `backup_backend` is `'s3'`. Default: `'puppet-cassandra-backups'`.
*   `profile_cassandra_pfpt::backup_upload_streaming` (Boolean): If `true`, the full backup script will stream the archive directly to S3 without creating a temporary file on disk, saving significant local disk space. Default: `false`.

## Puppet Agent Management

The base `cassandra_pfpt` component module includes logic to manage the Puppet agent itself by ensuring a scheduled run is in place via cron. This profile exposes the configuration for that feature.

*   **Scheduled Runs:** By default, the Puppet agent will run twice per hour at a staggered minute (e.g., at 15 and 45 minutes past the hour) to distribute the load on the Puppet primary server.
*   **Maintenance Window:** The cron job will **not** run if a file exists at `/var/lib/puppet-disabled`. Creating this file is the standard way to temporarily disable Puppet runs on a node during maintenance.
*   **Configuration:** You can override the default schedule by setting the `profile_cassandra_pfpt::puppet_cron_schedule` key in Hiera to a standard 5-field cron string.
## Backup and Restore

This profile provides a fully automated, S3-based backup solution using `systemd` timers and a collection of helper scripts. It also includes a powerful restore script to handle various recovery scenarios.

### Automated Backups

#### How It Works
1.  **Configuration:** You enable and configure backups through Hiera.
2.  **Puppet Setup:** Puppet creates `systemd` timer and service units on each Cassandra node.
3.  **Scheduling:** `systemd` automatically triggers the backup scripts based on the `OnCalendar` schedule you define.
4.  **Execution & Metadata Capture:** The scripts first generate a `backup_manifest.json` file containing critical metadata like the cluster name, node IP, datacenter, rack, and the node's token ranges. They then create a data snapshot, archive everything (data, schema, and manifest), and upload it to your specified S3 bucket. If `backup_upload_streaming` is enabled for full backups, the script builds the archive in memory and streams it directly to S3, avoiding local disk usage.
5.  **Local Snapshot Cleanup:** Before a new backup is taken, the script automatically cleans up any local snapshots that are older than the configured retention period (`profile_cassandra_pfpt::clearsnapshot_keep_days`). This provides a window for fast, local restores without filling up the disk.

#### Managed Systemd Units

When you enable backups via Hiera, this profile creates and manages the following `systemd` units on your Cassandra nodes. You can inspect them using commands like `systemctl status cassandra-full-backup.timer` or `journalctl -u cassandra-full-backup.service`.

*   **Full Backups**
    *   **Unit:** `cassandra-full-backup.timer` & `cassandra-full-backup.service`
    *   **Description:** This timer triggers a service that executes the `/usr/local/bin/full-backup-to-s3.sh` script.
    *   **Controlled By:** `profile_cassandra_pfpt::manage_full_backups: true`
    *   **Schedule:** Configured by `profile_cassandra_pfpt::full_backup_schedule`.

*   **Incremental Backups**
    *   **Unit:** `cassandra-incremental-backup.timer` & `cassandra-incremental-backup.service`
    *   **Description:** This timer triggers a service that executes the `/usr/local/bin/incremental-backup-to-s3.sh` script, which archives and uploads existing incremental backup files.
    *   **Controlled By:** `profile_cassandra_pfpt::manage_incremental_backups: true`
    *   **Schedule:** Configured by `profile_cassandra_pfpt::incremental_backup_schedule`.

#### Configuration Examples

##### Scenario 1: Production Backups with Streaming to Save Disk Space
This configuration is ideal for production nodes where local disk space is a concern during backups.

```yaml
# Hiera:
# Enable Cassandra's internal mechanism for creating incremental backup files
profile_cassandra_pfpt::incremental_backups: true

# Enable the full backup process via Puppet
profile_cassandra_pfpt::manage_full_backups: true
profile_cassandra_pfpt::full_backup_schedule: 'daily' # Runs at midnight

# Enable the incremental backup process via Puppet
profile_cassandra_pfpt::manage_incremental_backups: true
profile_cassandra_pfpt::incremental_backup_schedule: '0 */4 * * *' # Runs every 4 hours

# Define the S3 bucket for all backups
profile_cassandra_pfpt::backup_s3_bucket: 'my-prod-cassandra-backups'

# --- Enable streaming for full backups to save local disk space ---
profile_cassandra_pfpt::backup_upload_streaming: true
```

#### Hiera Parameters for Backups

*   `profile_cassandra_pfpt::incremental_backups` (Boolean): **Required for incremental backups.** Enables Cassandra's built-in feature to create hard links to new SSTables. Default: `false`.
*   `profile_cassandra_pfpt::manage_full_backups` (Boolean): Enables the scheduled `full-backup-to-s3.sh` script. Default: `false`.
*   `profile_cassandra_pfpt::manage_incremental_backups` (Boolean): Enables the scheduled `incremental-backup-to-s3.sh` script. Default: `false`.
*   `profile_cassandra_pfpt::backup_backend` (String): The storage backend to use for uploads. Currently only supports `'s3'`. If set to any other value, backups will be created locally but not uploaded or cleaned up, allowing for an external process to handle them. Default: `'s3'`.
*   `profile_cassandra_pfpt::full_backup_schedule` (String): The `systemd` OnCalendar schedule for full snapshot backups. Default: `'daily'`.
*   `profile_cassandra_pfpt::incremental_backup_schedule` (String | Array[String]): The `systemd` OnCalendar schedule(s) for incremental backups. Default: `'0 */4 * * *'`.
*   `profile_cassandra_pfpt::backup_s3_bucket` (String): The name of the S3 bucket to upload backups to. Default: `'puppet-cassandra-backups'`.
*   `profile_cassandra_pfpt::clearsnapshot_keep_days` (Integer): The number of days to keep snapshots locally on the node before they are automatically deleted. Set to 0 to disable local retention. Default: `3`.
*   `profile_cassandra_pfpt::full_backup_log_file` (String): Log file path for the full backup script. Default: `'/var/log/cassandra/full_backup.log'`.
*   `profile_cassandra_pfpt::incremental_backup_log_file` (String): Log file path for the incremental backup script. Default: `'/var/log/cassandra/incremental_backup.log'`.


### Restoring from a Backup

A `restore-from-s3.sh` script is placed in `/usr/local/bin` on each node to perform restores. This script supports three primary modes. Before taking any action, the script will first download and display the `backup_manifest.json` from the archive and require operator confirmation. This is a critical safety check to ensure you are restoring the correct data.

#### Mode 1: Full Node Restore (Destructive)
This mode is for recovering a completely failed node or for disaster recovery. It is a **destructive** operation.

**WARNING:** Running a full restore will **WIPE ALL CASSANDRA DATA** on the target node before restoring the backup.

##### Usage
1.  SSH into the node you want to restore.
2.  Identify the backup you want to restore. You need the full backup identifier (e.g., `full_snapshot_20231027120000`). You can restore from a local snapshot if it still exists, or from S3.
3.  Run the script with only the backup ID:
    ```bash
    sudo /usr/local/bin/restore-from-s3.sh <backup_identifier>
    ```
The script is intelligent: if it detects that the backup is from a different node (based on IP address), it will automatically configure the node to replace the old one, correctly assuming its identity and token ranges in the cluster.

#### Mode 2: Granular Restore (Keyspace or Table)
This mode is for recovering a specific table or an entire keyspace from a backup without affecting the rest of the cluster. It is a **non-destructive** operation that uses Cassandra's `sstableloader` tool to stream the backed-up data into the live cluster without downtime or affecting other data.

**Prerequisite:** The keyspace and table schema must already exist in the cluster before you can load data into it.

##### Usage
1.  SSH into any Cassandra node in the cluster.
2.  Identify the backup (full or incremental) that contains the data you want to restore.
3.  Run the script with the backup ID, keyspace name, and optionally the table name.

*   **To restore a single table:**
    ```bash
    sudo /usr/local/bin/restore-from-s3.sh <backup_id> <keyspace_name> <table_name>
    ```
*   **To restore an entire keyspace:**
    ```bash
    sudo /usr/local/bin/restore-from-s3.sh <backup_id> <keyspace_name>
    ```

#### Mode 3: Schema-Only Restore
This mode is the first step for a full cluster disaster recovery. It extracts the `schema.cql` file from a backup archive without touching the live node.

##### Usage
1.  SSH into one node of your new, empty cluster.
2.  Run the script with the `--schema-only` flag and a backup ID.
    ```bash
    sudo /usr/local/bin/restore-from-s3.sh --schema-only <backup_id>
    ```
3.  This extracts `schema.cql` to `/tmp/schema.cql`. You can then apply it to the cluster with `cqlsh`.

### Disaster Recovery: Restoring to a Brand New Cluster (Cold Start)

This procedure outlines how to restore a full cluster from S3 backups onto a set of brand-new machines where the old cluster is completely lost. The intelligent restore script automates the most complex parts of this process.

**The Strategy:** The script automatically detects if it's the first node being restored in an empty cluster.
-   **For the First Node:** It will use the `initial_token` property in `cassandra.yaml` to force the node to bootstrap with the correct identity and token ranges from the backup.
-   **For All Subsequent Nodes:** It will use the standard (and safer) `-Dcassandra.replace_address_first_boot` method to join the now-live cluster.

**Prerequisites:**
*   You have a set of full backups for each node from the old cluster in S3.
*   You have provisioned a new set of machines for the new cluster. Puppet should be applied, and the `cassandra` service should be stopped on all new nodes.

#### Step 1: Restore the Schema

The schema (definitions of keyspaces and tables) must be restored first.

1.  Choose **one node** in the new cluster to act as a temporary coordinator. Start the `cassandra` service on this node only. A single-node, empty cluster will form.
2.  SSH into that coordinator node.
3.  Choose a **full backup** from any of your old nodes to source the schema from. Run the `restore-from-s3.sh` script in schema-only mode:
    ```bash
    sudo /usr/local/bin/restore-from-s3.sh --schema-only <backup_id_of_any_old_node>
    ```
4.  This extracts `schema.cql` to `/tmp/schema.cql`. **Apply the schema to the new cluster:**
    ```bash
    cqlsh -u cassandra -p 'YourPassword' -f /tmp/schema.cql
    ```
5.  Once the schema is applied, **stop the cassandra service** on this coordinator node. The entire new cluster should now be offline.

#### Step 2: Perform a Rolling Restore of All Nodes

Now, simply restore each node, one at a time. The script handles the complexity.

1.  **On the first node** (e.g., `new-cassandra-1.example.com`):
    *   SSH into the node.
    *   Identify the backup ID of the old node it is replacing.
    *   Run the restore script in full restore mode:
        ```bash
        sudo /usr/local/bin/restore-from-s3.sh <backup_id_for_old_cassandra_1>
        ```
    *   The script will detect it's the first node, use `initial_token` to start, and wait for it to come online.

2.  **On the second node** (e.g., `new-cassandra-2.example.com`):
    *   Wait for the first node to be fully up (check with `nodetool status` from the first node).
    *   SSH into the second node.
    *   Run the restore script:
        ```bash
        sudo /usr/local/bin/restore-from-s3.sh <backup_id_for_old_cassandra_2>
        ```
    *   The script will detect a live seed node, so it will automatically use the `replace_address` method to join the cluster.

3.  **Repeat for all remaining nodes.** Continue the process, restoring one node at a time, until the entire cluster is back online.

Once all nodes have been restored, your cluster is fully recovered. The restore script automatically cleans up any temporary configuration changes (`initial_token` or `replace_address` flags) after each successful node start.
## Compaction Management

This profile deploys an intelligent script, `/usr/local/bin/compaction-manager.sh`, to help operators safely run manual compactions while monitoring disk space.

### Why Use the Compaction Manager?
Running a manual compaction (`nodetool compact`) can consume a significant amount of disk space temporarily. If a node runs out of space during compaction, it can lead to a critical failure. The `compaction-manager.sh` script prevents this by running the compaction process in the background while periodically checking disk space. If the free space drops below a critical threshold, it automatically stops the compaction process to prevent a disk-full error.

### Usage

The script can be run to target a specific table, an entire keyspace, or the whole node.

**To compact a specific table:**
```bash
sudo /usr/local/bin/compaction-manager.sh --keyspace my_app --table users
```

**To compact an entire keyspace:**
```bash
sudo /usr/local/bin/compaction-manager.sh --keyspace my_app
```

**To compact all keyspaces on a node:**
```bash
sudo /usr/local/bin/compaction-manager.sh
```

You can customize its behavior with flags:
*   `--critical <percent>`: Sets the critical free space percentage to abort at (Default: 15).
*   `--interval <seconds>`: Sets how often to check the disk (Default: 30).

All output and progress are logged to `/var/log/cassandra/compaction_manager.log`.

### Performing a Rolling Compaction (DC or Cluster-wide)

The `compaction-manager.sh` script operates on a single node. To perform a safe, rolling compaction across an entire datacenter or cluster, you should run the script sequentially on each node.

**Procedure:**
1.  SSH into the first node in the datacenter.
2.  Run the desired compaction command (e.g., `sudo /usr/local/bin/compaction-manager.sh -k my_keyspace`).
3.  Monitor the log file (`tail -f /var/log/cassandra/compaction_manager.log`) until the script reports "Compaction Manager Finished Successfully".
4.  Move to the next node in the datacenter and repeat steps 2-3.
5.  Continue this process until all nodes in the target group have been compacted.
## Garbage Collection

Similar to compaction, running a manual garbage collection can be managed safely using the `/usr/local/bin/garbage-collect.sh` script. This script is a wrapper around `nodetool garbagecollect` that provides important safety checks and targeting options.

### Why Use the Garbage Collection Script?
While less disk-intensive than a full compaction, running garbage collection still benefits from a pre-flight check to ensure the node has sufficient disk space before starting. The script prevents you from initiating the operation on a disk that is already nearing capacity.

### Usage
The script allows you to target the entire node, a specific keyspace, or one or more tables.

**To run garbage collection on the entire node:**
```bash
sudo /usr/local/bin/garbage-collect.sh
```

**To run on a specific keyspace:**
```bash
sudo /usr/local/bin/garbage-collect.sh -k my_keyspace
```

**To run on multiple tables within a keyspace:**
```bash
sudo /usr/local/bin/garbage-collect.sh -k my_app -t users -t audit_log
```

You can customize its behavior with flags:
*   `-g, --granularity <CELL|ROW>`: Sets the granularity of tombstones to remove (Default: `ROW`).
*   `-j, --jobs <num>`: Sets the number of concurrent sstable garbage collection jobs (Default: 0 for auto).
*   `-w, --warning <percent>`: Sets the warning free space percentage to abort at (Default: 30).
*   `-c, --critical <percent>`: Sets the critical free space percentage to abort at (Default: 20).

### Performing a Rolling Garbage Collection
To perform a safe, rolling garbage collection across an entire datacenter or cluster, you should run the script sequentially on each node, similar to the process for compaction. Wait for the script to complete successfully on one node before moving to the next.
## SSTable Upgrades

After a major Cassandra version upgrade (e.g., from 3.x to 4.x), you must run `nodetool upgradesstables` on each node to rewrite the SSTables into the new version's format. This profile deploys `/usr/local/bin/upgrade-sstables.sh` to manage this process safely.

### Why Use the Script?
The upgrade process writes new SSTables before deleting the old ones, which can significantly increase disk usage. This script performs a pre-flight disk check to ensure there is enough space before starting, preventing potential failures.

### Usage
Run the script sequentially on each node in the cluster, waiting for one to finish before starting the next.

**To upgrade SSTables on the entire node (most common):**
```bash
sudo /usr/local/bin/upgrade-sstables.sh
```

**To upgrade a specific keyspace:**
```bash
sudo /usr/local/bin/upgrade-sstables.sh -k my_app_keyspace
```

All output is logged to `/var/log/cassandra/upgradesstables.log`.
## Node Cleanup

When the token ring changes (e.g., a node is added to the cluster), you must run `nodetool cleanup` on existing nodes. This process removes data that no longer belongs to that node according to the new token assignments. This profile deploys `/usr/local/bin/cleanup-node.sh` to run this operation safely.

### Why Use the Script?
Running `cleanup` can be resource-intensive. This script provides a wrapper that adds pre-flight disk space checks to ensure the operation doesn't start on a node that is already low on space.

### Usage
`cleanup` should be run on a node *after* a new node has fully bootstrapped into the same datacenter. Run it sequentially on each existing node.

**To clean up the entire node:**
```bash
sudo /usr/local/bin/cleanup-node.sh
```

**To clean up a specific keyspace:**
```bash
sudo /usr/local/bin/cleanup-node.sh -k my_app_keyspace
```

All output is logged to `/var/log/cassandra/cleanup.log`.
## Limitations

This profile is primarily tested and supported on Red Hat Enterprise Linux and its derivatives (like CentOS, Rocky Linux). Support for other operating systems may require adjustments.
## Development

This module is generated and managed by Firebase Studio. Direct pull requests are not the intended workflow.
