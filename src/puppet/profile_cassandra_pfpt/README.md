# `profile_cassandra_pfpt`: A Complete Cassandra Operations Profile

> This module provides a complete profile for deploying and managing an Apache Cassandra node. It acts as a wrapper around the `cassandra_pfpt` component module, providing all its configuration data via Hiera lookups. This allows for a clean separation of logic from data.
>
> Beyond initial deployment, this profile equips each node with a powerful suite of automation and command-line tools to simplify and safeguard common operational tasks. The primary tool is `cass-ops`, a powerful command-line wrapper script.

---

## Table of Contents

1.  [Description](#description)
2.  [Setup](#setup)
3.  [Usage Examples](#usage-examples)
4.  [Operator's Quick Reference: The `cass-ops` Command](#operators-quick-reference-the-cass-ops-command)
5.  [Day-2 Operations Guide](#day-2-operations-guide)
    1.  [Node and Cluster Health Checks](#node-and-cluster-health-checks)
    2.  [Node Lifecycle Management](#node-lifecycle-management)
    3.  [Data and Maintenance Operations](#data-and-maintenance-operations)
6.  [Automated Maintenance Guide](#automated-maintenance-guide)
    1.  [Automated Backups](#automated-backups)
    2.  [Automated Repair](#automated-repair)
7.  [Backup & Recovery Guide](#backup--recovery-guide)
    1.  [Interactive Restore Wizard](#interactive-restore-wizard)
8.  [Puppet Architecture Guide](#puppet-architecture-guide)
9.  [Production Readiness Guide](#production-readiness-guide)
    1.  [Automated Service Monitoring and Restart](#automated-service-monitoring-and-restart)
    2.  [Monitoring Backups and Alerting](#monitoring-backups-and-alerting)
    3.  [Testing Your Disaster Recovery Plan (Fire Drills)](#testing-your-disaster-recovery-plan-fire-drills)
    4.  [Important Security and Cost Considerations](#important-security-and-cost-considerations)
10. [Hiera Parameter Reference](#hiera-parameter-reference)
11. [Puppet Agent Management](#puppet-agent-management)

---

## Description

This profile includes the `cassandra_pfpt` component module and provides it with a rich set of operational capabilities through Hiera-driven configuration and a suite of robust management scripts. The primary entry point for all operations is the `cass-ops` wrapper script, installed in `/usr/local/bin`.

## Setup

This profile is intended to be included by a role class.

```puppet
# In your role manifest (e.g., roles/manifests/cassandra.pp)
class role::cassandra {
  include profile_cassandra_pfpt
}
```

> All configuration for the node should be provided via your Hiera data source (e.g., in your `common.yaml` or node-specific YAML files). The backup scripts require the `jq`, `awscli`, and `openssl` packages, which this profile will install by default. The `cass-ops` tool also requires `python3-colorama` for color-coded output, which is also managed by the module.

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
profile_cassandra_pfpt::full_backup_schedule: '0 2 * * *' # cron spec
profile_cassandra_pfpt::manage_incremental_backups: true
profile_cassandra_pfpt::incremental_backup_schedule: '0 */4 * * *' # cron spec
profile_cassandra_pfpt::backup_s3_bucket: 'my-prod-cassandra-backups'
profile_cassandra_pfpt::clearsnapshot_keep_days: 7
profile_cassandra_pfpt::s3_retention_period: 30 # Keep backups in S3 for 30 days
profile_cassandra_pfpt::upload_streaming: false # Set to true to use faster but less-robust streaming uploads
profile_cassandra_pfpt::backup_throttle_rate: '20M/s' # Throttle automated backups to 20MB/s

# --- Automated Repair Configuration ---
profile_cassandra_pfpt::manage_scheduled_repair: true
profile_cassandra_pfpt::repair_schedule: '*-*-1/5 01:00:00' # Every 5 days
```

### Managing Cassandra Schema via Hiera

You can declaratively manage your entire Cassandra schema—users (roles), keyspaces, and tables—via Hiera. For production environments, it is highly recommended to encrypt passwords using **Hiera-eyaml**.

```yaml
# In your Hiera data
profile_cassandra_pfpt::schema_users:
  # Example with a plain-text password (suitable for development)
  'readonly_user':
    password: 'SafePassword123'
    is_superuser: false
    can_login: true
  # Example with a securely encrypted password using eyaml (for production)
  'app_admin':
    password: >
      ENC[PKCS7,MIIBojANBgkqhkiG9w0BAQEFAAOCAY8AMIIBigKCAYEAq3s4/L5W...9y9gBFdCIg4a5A==]
    is_superuser: true
    can_login: true

profile_cassandra_pfpt::schema_keyspaces:
  'my_app':
    ensure: 'present'
    replication:
      class: 'NetworkTopologyStrategy'
      dc1: 3
    durable_writes: true
  'my-test':
    ensure: 'present'
    replication:
      class: 'NetworkTopologyStrategy'
      dc1: 3
    durable_writes: true

profile_cassandra_pfpt::schema_tables:
  'users':
    ensure: 'present'
    keyspace: 'my_app'
    columns:
      - name: 'user_id'
        type: 'uuid'
      - name: 'first_name'
        type: 'text'
      - name: 'last_name'
        type: 'text'
    primary_key: 'user_id'
```

---

## Operator's Quick Reference: The `cass-ops` Command

This profile installs a unified administrative wrapper script, `cass-ops`, at `/usr/local/bin`. This is your primary entry point for all manual and automated operational tasks. It simplifies management by providing a single, memorable command with clear, grouped sub-commands.

To see all available commands, simply run `cass-ops` with no arguments or with `-h`.

```bash
$ sudo /usr/local/bin/cass-ops -h

usage: cass-ops [-h] <command> ...

Unified operations script for Cassandra.

Available Commands:
  {health,cluster-health,disk-health,version,stop,restart,reboot,drain,decommission,replace,rebuild,repair,cleanup,compact,garbage-collect,upgrade-sstables,backup,incremental-backup,backup-status,backup-verify,snapshot,restore,assassinate,stress,manual,upgrade-check,backup-guide,puppet-guide}

  health              Run a comprehensive health check on the local node.
  cluster-health      Quickly check cluster connectivity and nodetool status.
  disk-health         Check disk usage against warning/critical thresholds.
  version             Audit and print versions of key software (OS, Java, Cassandra).
  stop                Safely drain and stop the Cassandra service.
  restart             Perform a safe, rolling restart of the Cassandra service.
  reboot              Safely drain Cassandra and reboot the machine.
  drain               Drain the node, flushing memtables and stopping client traffic.
  decommission        Permanently remove this node from the cluster after streaming its data.
  replace             Configure this NEW, STOPPED node to replace a dead node.
  rebuild             Rebuild the data on this node by streaming from another datacenter.
  repair              Run a safe, manual full repair on the node. Can target a specific keyspace/table.
  cleanup             Run 'nodetool cleanup' with safety checks.
  compact             Run 'nodetool compact' with safety checks and advanced options.
  garbage-collect     Run 'nodetool garbagecollect' with safety checks.
  upgrade-sstables    Run 'nodetool upgradesstables' with safety checks.
  backup              Manually trigger a full, node-local backup to S3.
  incremental-backup  Manually trigger an incremental backup to S3.
  backup-status       Check the status of the last completed backup for a node.
  backup-verify       Verify the integrity and restorability of the latest backup set.
  snapshot            Take an ad-hoc snapshot with a generated tag.
  restore             Restore data from S3. Run without arguments for an interactive wizard.
  assassinate         Forcibly remove a dead node from the cluster's gossip ring.
  stress              Run 'cassandra-stress' via a robust wrapper.
  manual              Display the full operations manual in the terminal.
  upgrade-check       Run pre-flight checks before a major version upgrade.
  backup-guide        Display the full backup and recovery guide.
  puppet-guide        Display the Puppet architecture guide.

optional arguments:
  -h, --help            show this help message and exit

```
> **Note on legacy scripts:** The original `cassandra-admin.sh` script is also available for manual use if needed, but `cass-ops` is the primary and recommended tool for all operations.

---

## Day-2 Operations Guide

This section provides a practical guide for common operational tasks.

### Node and Cluster Health Checks

> Before performing any maintenance, always check the health of the node and cluster.

*   **Check the Local Node:** Run `sudo /usr/local/bin/cass-ops health`. This script is your first stop. It checks disk space, node status (UN), gossip state, active streams, and recent log exceptions, giving you a quick "go/no-go" for maintenance.
*   **Check Cluster Connectivity:** Run `sudo /usr/local/bin/cass-ops cluster-health`. This verifies that the node can communicate with the cluster and that the CQL port is open.
*   **Check Disk Space Manually:** Run `sudo /usr/local/bin/cass-ops disk-health` to see the current free space percentage on the data volume.

### Node Lifecycle Management

#### Performing a Safe Rolling Restart
To apply configuration changes or for other maintenance, always use the provided script for a safe restart.

1.  SSH into the node you wish to restart.
2.  Execute `sudo /usr/local/bin/cass-ops restart`.
3.  The script will automatically drain the node, stop the service, start it again, and wait until it verifies the node has successfully rejoined the cluster in `UN` state.

#### Decommissioning a Node
When you need to permanently remove a node from the cluster:

1.  SSH into the node you want to remove.
2.  Run `sudo /usr/local/bin/cass-ops decommission`.
3.  The script will ask for confirmation, then run `nodetool decommission`. After it completes successfully, it is safe to shut down and terminate the instance.

#### Replacing a Failed Node
If a node has failed permanently and cannot be recovered, you must replace it with a new one.

1.  Provision a new machine with the same resources and apply this Puppet profile. **Do not start the Cassandra service.**
2.  SSH into the **new, stopped** node.
3.  Execute the `replace` command, providing the IP of the dead node it is replacing:
    ```bash
    sudo /usr/local/bin/cass-ops replace <ip_of_dead_node>
    ```
4.  The script will configure the necessary JVM flag (`-Dcassandra.replace_address_first_boot`).
5.  You can now **start the Cassandra service** on the new node. It will automatically bootstrap into the cluster, assuming the identity and token ranges of the dead node.

### Data and Maintenance Operations

#### Repairing Data
This is the primary script for running manual repairs. It intelligently breaks the repair into small token ranges to minimize performance impact.

*   **To repair all keyspaces (most common):**
    ```bash
    sudo /usr/local/bin/cass-ops repair
    ```
*   **To repair a specific keyspace:**
    ```bash
    sudo /usr/local/bin/cass-ops repair my_keyspace
    ```
> Run this sequentially on each node in the cluster for a full, safe, rolling repair.

#### Compaction
To manually trigger compaction while safely monitoring disk space:

```bash
# Compact a specific table
sudo /usr/local/bin/cass-ops compact -- -k my_keyspace -t my_table

# Compact an entire keyspace
sudo /usr/local/bin/cass-ops compact -- -k my_keyspace
```

#### Garbage Collection
To manually remove droppable tombstones with pre-flight safety checks:

```bash
sudo /usr/local/bin/cass-ops garbage-collect -- -k my_keyspace -t users
```

#### SSTable Upgrades
After a major Cassandra version upgrade, run this on each node sequentially:

```bash
sudo /usr/local/bin/cass-ops upgrade-sstables
```

#### Node Cleanup
After adding a new node to the cluster, run `cleanup` on the existing nodes in the same DC to remove data that no longer belongs to them.

```bash
sudo /usr/local/bin/cass-ops cleanup
```

---

## Automated Maintenance Guide

### Automated Backups

This profile provides a fully automated, S3-based backup solution using `cron`.

#### How It Works
1.  **Granular Backups:** Backups are no longer single, large archives. Instead, each table (for full backups) or set of incremental changes is archived and uploaded as a small, separate file to S3.
2.  **Scheduling:** Puppet creates `cron` jobs in `/etc/cron.d/` on each node.
3.  **Execution:** `cron` automatically triggers the backup scripts via `cass-ops`.
4.  **Process:** The scripts generate a `backup_manifest.json` with critical metadata for each backup run (identified by a `YYYY-MM-DD-HH-MM` timestamp), encrypt the archives, and upload them to a structured path in S3.
5.  **Local Snapshot Cleanup:** The full backup script automatically deletes local snapshots older than `clearsnapshot_keep_days`.
6.  **S3 Lifecycle Management:** The full backup script also ensures an S3 lifecycle policy is in place on the bucket to automatically delete old backups after the `s3_retention_period`.

#### Pausing Backups
> To temporarily disable backups on a node for maintenance, create a flag file:
> `sudo touch /var/lib/backup-disabled`.
> To re-enable, simply remove the file.

### Automated Repair

A safe, low-impact, automated repair process is critical for data consistency.

#### How it Works
1.  **Configuration:** Enable via `profile_cassandra_pfpt::manage_scheduled_repair: true`.
2.  **Scheduling:** Puppet creates a `systemd` timer (`cassandra-repair.timer`) that, by default, runs every 5 days to align with a 10-day `gc_grace_seconds`.
3.  **Execution:** The timer runs `cass-ops repair`, which executes the intelligent Python script to repair the node in small, manageable chunks, minimizing performance impact.
4.  **Control:** You can manually stop, start, or check the status of a repair using `systemd` commands:
    *   `sudo systemctl stop cassandra-repair.service` (To kill a running repair)
    *   `sudo systemctl start cassandra-repair.service` (To manually start a repair)
    *   `sudo systemctl stop cassandra-repair.timer` (To pause the automated schedule)

---

## Backup & Recovery Guide

The backup and recovery process for this Cassandra deployment is documented in a complete, standalone guide. This document covers the architecture, backup creation, all `cass-ops restore` commands, and step-by-step walkthroughs for various disaster recovery scenarios.

**This is the single source of truth for all recovery operations.**

To view this guide, run the following command on any Cassandra node:
```bash
sudo cass-ops backup-guide
```

### Interactive Restore Wizard

To make the restore process safer and more user-friendly, an interactive wizard is available. It guides the operator step-by-step through selecting a restore type, source host, and point-in-time, reducing the chance of human error.

To start the wizard, simply run the `restore` command with no arguments:
```bash
sudo cass-ops restore
```

---

## Puppet Architecture Guide

A complete guide to the Puppet automation architecture (the Roles and Profiles pattern, Hiera data flow, etc.) is available as a standalone document.

To view this guide, run the following command on any Cassandra node:
```bash
sudo cass-ops puppet-guide
```

---

## Production Readiness Guide

Having functional backups is the first step. Ensuring they are reliable and secure is the next.

### Automated Service Monitoring and Restart

This module uses the native capabilities of `systemd` to ensure the Cassandra service remains running. If the Cassandra process crashes or is terminated unexpectedly, `systemd` will automatically attempt to restart it.

*   **How it Works:** Puppet creates a `systemd` override file that configures `Restart=always` and `RestartSec=10`.
*   **Monitoring:** While this provides automatic recovery, it's still critical to have external alerting (e.g., via Prometheus) to notify you *when* a restart has occurred.

### Monitoring Backups and Alerting

A backup that fails silently is not a backup.
*   **Manual Checks:** Check the dedicated backup logs: `/var/log/cassandra/full_backup.log` and `/var/log/cassandra/incremental_backup.log`.
*   **Automated Alerting (Recommended):** Create alerts in your monitoring system that trigger if a backup log has not been updated in 24 hours or if it contains "ERROR".

### Testing Your Disaster Recovery Plan (Fire Drills)

The only way to trust your backups is to **test them regularly**. At least once per quarter, provision an isolated test environment and perform a full "Cold Start DR" by following the comprehensive backup and recovery guide.

### Important Security and Cost Considerations

*   **Encryption Key Management:** The `backup_encryption_key` is your most critical secret. It should be managed in Hiera-eyaml. **You must securely store all old keys** that were used for previous backups, as you will need them to restore from those older backups.
*   **S3 Cost Management:** The backup script automatically manages a lifecycle policy to expire objects after `s3_retention_period` days. For more advanced strategies (e.g., moving to Glacier), configure them directly on the S3 bucket.
*   **Cross-Region Disaster Recovery:** To protect against a full AWS region failure, enable S3 Cross-Region Replication on your backup bucket.

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

### Service Management
*   `profile_cassandra_pfpt::service_restart` (String): The `Restart` policy for the `systemd` service. Can be `no`, `on-success`, `on-failure`, `on-abnormal`, `on-watchdog`, `on-abort`, or `always`. Default: `'always'`.
*   `profile_cassandra_pfpt::service_restart_sec` (Integer): The number of seconds to wait before restarting the service. Default: `10`.

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

### Security & Schema
*   `profile_cassandra_pfpt::authenticator` (String): The authentication backend. Default: `'PasswordAuthenticator'`.
*   `profile_cassandra_pfpt::authorizer` (String): The authorization backend. Default: `'CassandraAuthorizer'`.
*   `profile_cassandra_pfpt::role_manager` (String): The role management backend. Default: `'CassandraRoleManager'`.
*   `profile_cassandra_pfpt::system_keyspaces_replication` (Hash): Defines the replication factor for system keyspaces in a multi-DC setup. Example: `{ 'dc1' => 3, 'dc2' => 3 }`. Default: `{}`.
*   `profile_cassandra_pfpt::schema_users` (Hash): A hash defining user accounts. Default: `{}`.
*   `profile_cassandra_pfpt::schema_keyspaces` (Hash): A hash defining keyspaces. Default: `{}`.
*   `profile_cassandra_pfpt::schema_tables` (Hash): A hash defining tables. Default: `{}`.
*   `profile_cassandra_pfpt::schema_cql_types` (Hash): A hash defining user-defined types. Default: `{}`.

### Automated Maintenance
*   `profile_cassandra_pfpt::manage_scheduled_repair` (Boolean): Set to `true` to enable the automated weekly repair job. Default: `false`.
*   `profile_cassandra_pfpt::repair_schedule` (String): The `systemd` OnCalendar schedule for the automated repair job. Default: `'*-*-1/5 01:00:00'`. This schedules the repair to run every 5 days, which is a safe interval for a 10-day `gc_grace_seconds`.
*   `profile_cassandra_pfpt::repair_keyspace` (String): If set, the automated repair job will only repair this specific keyspace. If unset, it repairs all non-system keyspaces. Default: `undef`.
*   `profile_cassandra_pfpt::manage_full_backups` (Boolean): Enables the scheduled full backup script. Default: `false`.
*   `profile_cassandra_pfpt::manage_incremental_backups` (Boolean): Enables the scheduled incremental backup script. Default: `false`.
*   `profile_cassandra_pfpt::full_backup_schedule` (String): The cron schedule for the automated full backup job. Default: `'0 2 * * *'` (Daily at 2am).
*   `profile_cassandra_pfpt::incremental_backup_schedule` (String): The cron schedule for the automated incremental backup job. Default: `'0 */4 * * *'` (Every 4 hours).
*   `profile_cassandra_pfpt::backup_encryption_key` (Sensitive[String]): The secret key used to encrypt all backup archives. **WARNING:** This has an insecure default value to prevent Puppet runs from failing. You **MUST** override this with a strong, unique secret in your production Hiera data. Default: `'MustBeChanged-ChangeMe-ChangeMe!!'`.
*   `profile_cassandra_pfpt::backup_backend` (String): The storage backend to use for uploads. Set to `'local'` to disable uploads. Default: `'s3'`.
*   `profile_cassandra_pfpt::backup_s3_bucket` (String): The name of the S3 bucket to use when `backup_backend` is `'s3'`. Defaults to a sanitized version of the cluster name.
*   `profile_cassandra_pfpt::s3_retention_period` (Integer): The number of days to keep backups in S3 before they are automatically deleted by a lifecycle policy. The policy is applied automatically by the backup script. Set to 0 to disable. Default: `15`.
*   `profile_cassandra_pfpt::backup_s3_object_lock_enabled` (Boolean): Enables S3 Object Lock for WORM (Write-Once, Read-Many) protection on all backup files. The S3 bucket MUST be created with Object Lock enabled for this to work. Default: `false`.
*   `profile_cassandra_pfpt::backup_s3_object_lock_mode` (String): Sets the lock mode. Can be `GOVERNANCE` (allows bypass with special permissions) or `COMPLIANCE` (absolute lock). Default: `'GOVERNANCE'`.
*   `profile_cassandra_pfpt::backup_s3_object_lock_retention_days` (Integer): The number of days each backup object is locked for. Defaults to the value of `s3_retention_period`.
*   `profile_cassandra_pfpt::clearsnapshot_keep_days` (Integer): The number of days to keep local snapshots on the node before they are automatically deleted. Set to 0 to disable. Default: `3`.
*   `profile_cassandra_pfpt::upload_streaming` (Boolean): Whether to use a direct streaming pipeline for backups (`true`) or a more robust method using temporary files (`false`). Streaming is faster but can hide errors. Default: `false`.
*   `profile_cassandra_pfpt::backup_parallelism` (Integer): The number of concurrent tables to process during backup or restore operations. Default: `4`.
*   `profile_cassandra_pfpt::backup_throttle_rate` (String): Throttles the network bandwidth for automated backup jobs. The value is passed to the AWS CLI (e.g., `'20M/s'`, `'1G/s'`). Default: `undef` (no throttling).
*   `profile_cassandra_pfpt::backup_exclude_keyspaces` (Array[String]): A list of keyspace names to exclude from backups. Default: `[]`.
    ```yaml
    # Example:
    profile_cassandra_pfpt::backup_exclude_keyspaces:
      - 'metrics_keyspace'
      - 'temp_data'
    ```
*   `profile_cassandra_pfpt::backup_exclude_tables` (Array[String]): A list of specific tables to exclude, in `'keyspace.table'` format. Default: `[]`.
    ```yaml
    # Example:
    profile_cassandra_pfpt::backup_exclude_tables:
      - 'my_app.audit_logs'
      - 'my_app.session_data'
    ```
*   `profile_cassandra_pfpt::backup_include_only_keyspaces` (Array[String]): If set, **only** keyspaces in this list will be backed up. Default: `[]`.
    ```yaml
    # Example:
    profile_cassandra_pfpt::backup_include_only_keyspaces:
      - 'billing'
      - 'user_data'
    ```
*   `profile_cassandra_pfpt::backup_include_only_tables` (Array[String]): If set, **only** tables in this list (in `'keyspace.table'` format) will be backed up. Takes precedence over `backup_include_only_keyspaces`. Default: `[]`.
    ```yaml
    # Example:
    profile_cassandra_pfpt::backup_include_only_tables:
      - 'user_data.profiles'
      - 'user_data.settings'
    ```
*   `profile_cassandra_pfpt::manage_stress_test` (Boolean): Set to `true` to install the `cassandra-stress` tools and the `/usr/local/bin/stress-test.sh` wrapper script. Default: `false`.

### Monitoring & Agent Integrations
*   `profile_cassandra_pfpt::manage_node_exporter` (Boolean): Set to `true` to install and enable the Prometheus Node Exporter for system-level metrics. Default: `false`.
*   `profile_cassandra_pfpt::node_exporter_install_method` (String): How to install Node Exporter. Can be `'url'` (default), `'package'`, or `'source'`. If using `'source'`, you must place the `node_exporter` binary in the `cassandra_pfpt/files/` directory of the module.
*   `profile_cassandra_pfpt::node_exporter_package_name` (String): The package name to install if using the `package` method. Default: `'node_exporter'`.
*   `profile_cassandra_pfpt::node_exporter_package_ensure` (String): The `ensure` state for the package resource. Default: `'installed'`.
*   `profile_cassandra_pfpt::node_exporter_version` (String): The version of Node Exporter to install when using the `url` method. Default: `'1.7.0'`.
*   `profile_cassandra_pfpt::node_exporter_download_url_base` (String): **(Required if using `install_method: url`)** The base URL for downloading the Node Exporter archive. There is no default.
*   `profile_cassandra_pfpt::manage_jmx_exporter` (Boolean): Set to `true` to enable the Prometheus JMX exporter for Cassandra-specific metrics. Default: `false`.
*   `profile_cassandra_pfpt::jmx_exporter_port` (Integer): The port for the JMX exporter to listen on. Default: `9404`.
*   `profile_cassandra_pfpt::manage_coralogix_agent` (Boolean): Set to `true` to install and configure the Coralogix agent. Default: `false`.
*   `profile_cassandra_pfpt::coralogix_api_key` (Sensitive[String]): Your Coralogix private key. Required if `manage_coralogix_agent` is true. Default: `''`.
*   `profile_cassandra_pfpt::coralogix_region` (String): Your Coralogix region (e.g., 'US', 'Europe'). Default: `'US'`.
*   `profile_cassandra_pfpt::coralogix_application_name` (String): The application name to tag logs and metrics with. Default: `'cassandra'`.
*   `profile_cassandra_pfpt::coralogix_subsystem_name` (String): The subsystem name to tag logs and metrics with. Defaults to the cluster name.
*   `profile_cassandra_pfpt::coralogix_log_files` (Hash): A hash mapping a display name to a log file path to be monitored. Default: `{ 'Cassandra System' => '/var/log/cassandra/system.log', 'Cassandra GC' => '/var/log/cassandra/gc.log' }`.
*   `profile_cassandra_pfpt::coralogix_jmx_metrics` (Array[String]): An array of JMX MBeans to collect as metrics. Default: A list of key latency and load metrics.
*   `profile_cassandra_pfpt::coralogix_jmx_endpoint` (String): The JMX endpoint for the agent to connect to. Default: `'service:jmx:rmi:///jndi/rmi://localhost:7199/jmxrmi'`.

### Puppet Agent Management
*   `profile_cassandra_pfpt::manage_puppet_agent_cron` (Boolean): Enables or disables the management of the Puppet agent cron job. Default: `false`.
*   `profile_cassandra_pfpt::puppet_cron_schedule` (String): The 5-field cron schedule for the Puppet agent run. Default: A staggered schedule running twice per hour.

---

## Puppet Agent Management

This profile can manage the Puppet agent's cron job to ensure regular configuration runs. By default, this is **disabled**.

*   **Enabling:** To enable, set `profile_cassandra_pfpt::manage_puppet_agent_cron: true` in your Hiera data.
*   **Scheduled Runs:** When enabled, the Puppet agent will run twice per hour at a staggered minute by default.
*   **Maintenance Window:** The cron job will **not** run if a file exists at `/var/lib/puppet-disabled`. Creating this file is the standard way to temporarily disable Puppet runs.
*   **Configuration:** You can override the default schedule by setting the `profile_cassandra_pfpt::puppet_cron_schedule` key in Hiera to a standard 5-field cron string.

    

    
