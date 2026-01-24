# `profile_cassandra_pfpt`: A Complete Cassandra Operations Profile

> This module provides a complete profile for deploying and managing an Apache Cassandra node. It acts as a wrapper around the `cassandra_pfpt` component module, providing all of its configuration data via Hiera lookups. This allows for a clean separation of logic from data.
>
> Beyond initial deployment, this profile equips each node with a powerful suite of automation and command-line tools to simplify and safeguard common operational tasks, from health checks and backups to complex disaster recovery scenarios.

---

## Table of Contents

1.  [Description](#description)
2.  [Setup](#setup)
3.  [Usage Examples](#usage-examples)
4.  [Operator's Quick Reference: The `cassandra-admin` Command](#operators-quick-reference-the-cassandra-admin-command)
5.  [Day-2 Operations Guide](#day-2-operations-guide)
    1.  [Node and Cluster Health Checks](#node-and-cluster-health-checks)
    2.  [Node Lifecycle Management](#node-lifecycle-management)
    3.  [Data and Maintenance Operations](#data-and-maintenance-operations)
6.  [Automated Maintenance Guide](#automated-maintenance-guide)
    1.  [Automated Backups](#automated-backups)
    2.  [Automated Repair](#automated-repair)
7.  [Disaster Recovery Guide: A Deep Dive into Point-in-Time Recovery](#disaster-recovery-guide-a-deep-dive-into-point-in-time-recovery)
    1.  [Understanding the Backup Strategy](#understanding-the-backup-strategy)
    2.  [The Restore Process: Building the Chain](#the-restore-process-building-the-chain)
    3.  [Restore Scenario 1: Granular Restore (Live Cluster)](#restore-scenario-1-granular-restore-live-cluster)
    4.  [Restore Scenario 2: Full Node Restore (Replacing a Single Failed Node)](#restore-scenario-2-full-node-restore-replacing-a-single-failed-node)
    5.  [Restore Scenario 3: Full Cluster Restore (Cold Start DR)](#restore-scenario-3-full-cluster-restore-cold-start-dr)
    6.  [Restore Scenario 4: Recovering from Accidental Schema Changes](#restore-scenario-4-recovering-from-accidental-schema-changes)
8.  [Production Readiness Guide](#production-readiness-guide)
    1.  [Automated Service Monitoring and Restart](#automated-service-monitoring-and-restart)
    2.  [Monitoring Backups and Alerting](#monitoring-backups-and-alerting)
    3.  [Testing Your Disaster Recovery Plan (Fire Drills)](#testing-your-disaster-recovery-plan-fire-drills)
    4.  [Important Security and Cost Considerations](#important-security-and-cost-considerations)
9.  [Hiera Parameter Reference](#hiera-parameter-reference)
10. [Puppet Agent Management](#puppet-agent-management)

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
profile_cassandra_pfpt::full_backup_schedule: '*-*-* 02:00:00' # systemd timer spec
profile_cassandra_pfpt::manage_incremental_backups: true
profile_cassandra_pfpt::incremental_backup_schedule: '*-*-* 0/4:00:00' # systemd timer spec
profile_cassandra_pfpt::backup_s3_bucket: 'my-prod-cassandra-backups'
profile_cassandra_pfpt::clearsnapshot_keep_days: 7
profile_cassandra_pfpt::s3_retention_period: 30 # Keep backups in S3 for 30 days
profile_cassandra_pfpt::upload_streaming: false # Set to true to use faster but less-robust streaming uploads

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

## Operator's Quick Reference: The `cassandra-admin` Command

This profile installs a unified administrative wrapper script at `/usr/local/bin/cassandra-admin`. This is your primary entry point for all manual operational tasks. It simplifies management by providing a single, memorable command with clear sub-commands.

To see all available commands, simply run it with `help`:

```
$ sudo /usr/local/bin/cassandra-admin help

Cassandra Operations Master Script

A unified wrapper for managing common Cassandra operational tasks on this node.

Usage: /usr/local/bin/cassandra-admin <command> [arguments...]

--- Node & Cluster Status ---
  health                 Run a comprehensive health check on the local node.
  cluster-health         Quickly check cluster connectivity and nodetool status.
  disk-health            Check disk usage against warning/critical thresholds. Usage: disk-health [-p /path] [-w 80] [-c 90]
  version                Audit and print versions of key software (OS, Java, Cassandra).

--- Node Lifecycle & Maintenance ---
  stop                   Safely drain and stop the Cassandra service.
  restart                Perform a safe, rolling restart of the Cassandra service.
  reboot                 Safely drain Cassandra and reboot the machine.
  drain                  Drain the node, flushing memtables and stopping client traffic.
  decommission           Permanently remove this node from the cluster after streaming its data.
  replace <dead_node_ip> Configure this NEW, STOPPED node to replace a dead node.
  rebuild <source_dc>    Rebuild the data on this node by streaming from another datacenter.

--- Data Management & Repair ---
  repair [<keyspace>]    Run a safe, granular repair on the node's token ranges. Can target a specific keyspace.
  cleanup [opts]         Run 'nodetool cleanup' with safety checks. Use 'cleanup -- --help' for options.
  compact [opts]         Run 'nodetool compact' with safety checks. Use 'compact -- --help' for options.
  garbage-collect [opts] Run 'nodetool garbagecollect' with safety checks. Use 'garbage-collect -- --help' for options.
  upgrade-sstables [opts]Run 'nodetool upgradesstables' with safety checks. Use 'upgrade-sstables -- --help' for options.

--- Backup & Recovery ---
  backup                 Manually trigger a full, node-local backup to S3.
  backup-status          Check the status of the last completed backup for a node.
  snapshot [<keyspaces>] Take an ad-hoc snapshot with a generated tag. Optionally specify comma-separated keyspaces.
  restore [opts]         Restore data from S3 backups. This is a complex command; run 'restore -- --help' for its usage.

--- Advanced & Destructive Operations (Use with caution!) ---
  assassinate <dead_node_ip> Forcibly remove a dead node from the cluster's gossip ring.

--- Performance Testing ---
  stress [opts]          Run 'cassandra-stress' via a robust wrapper. Run 'stress -- --help' for options.
```

---

## Day-2 Operations Guide

This section provides a practical guide for common operational tasks.

### Node and Cluster Health Checks

> Before performing any maintenance, always check the health of the node and cluster.

*   **Check the Local Node:** Run `sudo /usr/local/bin/cassandra-admin health`. This script is your first stop. It checks disk space, node status (UN), gossip state, active streams, and recent log exceptions, giving you a quick "go/no-go" for maintenance.
*   **Check Cluster Connectivity:** Run `sudo /usr/local/bin/cassandra-admin cluster-health`. This verifies that the node can communicate with the cluster and that the CQL port is open.
*   **Check Disk Space Manually:** Run `sudo /usr/local/bin/cassandra-admin disk-health` to see the current free space percentage on the data volume.

### Node Lifecycle Management

#### Performing a Safe Rolling Restart
To apply configuration changes or for other maintenance, always use the provided script for a safe restart.

1.  SSH into the node you wish to restart.
2.  Execute `sudo /usr/local/bin/cassandra-admin restart`.
3.  The script will automatically drain the node, stop the service, start it again, and wait until it verifies the node has successfully rejoined the cluster in `UN` state.

#### Decommissioning a Node
When you need to permanently remove a node from the cluster:

1.  SSH into the node you want to remove.
2.  Run `sudo /usr/local/bin/cassandra-admin decommission`.
3.  The script will ask for confirmation, then run `nodetool decommission`. After it completes successfully, it is safe to shut down and terminate the instance.

#### Replacing a Failed Node
If a node has failed permanently and cannot be recovered, you must replace it with a new one.

1.  Provision a new machine with the same resources and apply this Puppet profile. **Do not start the Cassandra service.**
2.  SSH into the **new, stopped** node.
3.  Execute the `replace` command, providing the IP of the dead node it is replacing:
    ```bash
    sudo /usr/local/bin/cassandra-admin replace <ip_of_dead_node>
    ```
4.  The script will configure the necessary JVM flag (`-Dcassandra.replace_address_first_boot`).
5.  You can now **start the Cassandra service** on the new node. It will automatically bootstrap into the cluster, assuming the identity and token ranges of the dead node.

### Data and Maintenance Operations

#### Repairing Data
This is the primary script for running manual repairs. It intelligently breaks the repair into small token ranges to minimize performance impact.

*   **To repair all keyspaces (most common):**
    ```bash
    sudo /usr/local/bin/cassandra-admin repair
    ```
*   **To repair a specific keyspace:**
    ```bash
    sudo /usr/local/bin/cassandra-admin repair my_keyspace
    ```
> Run this sequentially on each node in the cluster for a full, safe, rolling repair.

#### Compaction
To manually trigger compaction while safely monitoring disk space:

```bash
# Compact a specific table
sudo /usr/local/bin/cassandra-admin compact -- -k my_keyspace -t my_table

# Compact an entire keyspace
sudo /usr/local/bin/cassandra-admin compact -- -k my_keyspace
```

#### Garbage Collection
To manually remove droppable tombstones with pre-flight safety checks:

```bash
sudo /usr/local/bin/cassandra-admin garbage-collect -- -k my_keyspace -t users
```

#### SSTable Upgrades
After a major Cassandra version upgrade, run this on each node sequentially:

```bash
sudo /usr/local/bin/cassandra-admin upgrade-sstables
```

#### Node Cleanup
After adding a new node to the cluster, run `cleanup` on the existing nodes in the same DC to remove data that no longer belongs to them.

```bash
sudo /usr/local/bin/cassandra-admin cleanup
```

---

## Automated Maintenance Guide

### Automated Backups

This profile provides a fully automated, S3-based backup solution using `systemd` timers.

#### How It Works
1.  **Granular Backups:** Backups are no longer single, large archives. Instead, each table (for full backups) or set of incremental changes is archived and uploaded as a small, separate file to S3.
2.  **Scheduling:** Puppet creates `systemd` service and timer units on each node (e.g., `cassandra-full-backup.timer`).
3.  **Execution:** `systemd` automatically triggers the backup scripts (`full-backup-to-s3.sh`, `incremental-backup-to-s3.sh`) based on the `OnCalendar` schedule.
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
3.  **Execution:** The timer runs the `range-repair.sh` script, which executes the intelligent Python script to repair the node in small, manageable chunks, minimizing performance impact.
4.  **Control:** You can manually stop, start, or check the status of a repair using `systemd` commands:
    *   `sudo systemctl stop cassandra-repair.service` (To kill a running repair)
    *   `sudo systemctl start cassandra-repair.service` (To manually start a repair)
    *   `sudo systemctl stop cassandra-repair.timer` (To pause the automated schedule)

---

## Disaster Recovery Guide: A Deep Dive into Point-in-Time Recovery

This guide provides an in-depth, step-by-step walkthrough for recovering your Cassandra cluster from S3 backups using the powerful `cassandra-admin restore` command.

### Understanding the Backup Strategy

Before restoring, it's critical to understand how backups are structured:

*   **Backup Sets:** Each backup run (full or incremental) creates a "backup set" in S3, identified by a timestamp tag (e.g., `2026-01-20-18-00`).
*   **Granular Archives:** Inside a backup set, data for each table is stored in its own encrypted archive (`.tar.gz.enc`).
*   **Manifest File:** Every backup set contains a `backup_manifest.json`. This file is the key to recovery, containing metadata about the backup type (full/incremental), the node's identity (IP, DC, rack, tokens), and which tables were included.
*   **Schema Dump:** Full backups also include a `schema.cql` file, which is a complete snapshot of the database schema (`CREATE KEYSPACE`, `CREATE TABLE` statements). This is essential for full cluster recovery.
*   **Schema-to-Directory Mapping:** A `schema_mapping.json` file is included to map human-readable table names to their internal UUID-based directory names, which is critical for handling schema changes over time.

### The Restore Process: Building the Chain

The `cassandra-admin restore` script performs Point-in-Time Recovery (PITR). When you provide a target timestamp with `--date`:

1.  **Find the Base:** It searches S3 for the most recent **full** backup that occurred *at or before* your target time. This is the foundation of the restore.
2.  **Find the Deltas:** It then finds all **incremental** backups that occurred *between* the full backup and your target time.
3.  **Build the Chain:** It assembles this list of backups into a "restore chain" (full backup + subsequent incrementals).
4.  **Confirm and Execute:** It presents this chain to you for confirmation before proceeding with the restore, ensuring you know exactly what will be applied.

---

### Restore Scenario 1: Granular Restore (Live Cluster)

> **Use Case:** Restoring a specific table or keyspace that was accidentally dropped or corrupted, without taking the cluster offline.

This is a non-destructive operation that streams data into a **live, running cluster**.

#### Steps:

1.  SSH into any Cassandra node in the cluster.
2.  Choose the appropriate restore action:
    *   `--download-and-restore`: The most common action. It downloads the data and immediately loads it using `sstableloader`.
    *   `--download-only`: Downloads and decrypts the data to `/var/lib/cassandra/restore_download/` for manual inspection. The data is **not** loaded into the cluster.

#### Example Commands:

```bash
# Example 1: Restore a single table ('users') to its state as of 6:00 PM on Jan 20, 2026.
# The script will find the correct backup chain and load the data.
sudo /usr/local/bin/cassandra-admin restore -- \
  --date "2026-01-20-18-00" \
  --keyspace my_app \
  --table users \
  --download-and-restore

# Example 2: Restore an entire keyspace ('auditing').
sudo /usr/local/bin/cassandra-admin restore -- \
  --date "2026-01-20-18-00" \
  --keyspace auditing \
  --download-and-restore

# Example 3: Download data for a table for inspection without loading it.
sudo /usr/local/bin/cassandra-admin restore -- \
  --date "2026-01-20-18-00" \
  --keyspace my_app \
  --table users \
  --download-only
```
> **Important:** The script intelligently handles table UUID mismatches. If the live table has a different UUID than the backed-up data, the script will automatically rename the downloaded directory to match the live one before loading.

---

### Restore Scenario 2: Full Node Restore (Replacing a Single Failed Node)

> **Use Case:** A single node has failed permanently (e.g., hardware failure) and you need to replace it with a new machine, restoring its data and identity.

This is a **destructive** operation performed on a **new, stopped node**.

#### Prerequisites:

*   You have provisioned a new machine.
*   You have applied the Puppet profile to it.
*   The `cassandra` service is **stopped** on this new node.

#### Steps:

1.  SSH into the **new, stopped** node.
2.  Execute the restore script in `--full-restore` mode. Crucially, you must use `--source-host` to specify the hostname of the *original, dead node* you are replacing.
    ```bash
    # Restore this new node using the backup data from 'cassandra-node-03.example.com'
    # to the point in time of the latest available backup.
    sudo /usr/local/bin/cassandra-admin restore -- \
      --date "2026-01-22-10-00" \
      --source-host cassandra-node-03.example.com \
      --full-restore \
      --yes
    ```
3.  The script will:
    *   Wipe any existing Cassandra data directories.
    *   Download the manifest from the dead node's backup to retrieve its unique ring tokens.
    *   Configure `cassandra.yaml` with these tokens, ensuring the new node assumes the correct identity in the ring.
    *   Download and extract the full data set from the specified backup chain.
    *   Start the Cassandra service and verify it rejoins the cluster as `UN` (Up/Normal).

---

### Restore Scenario 3: Full Cluster Restore (Cold Start DR)

> **Use Case:** A catastrophic failure has destroyed the entire cluster. You need to rebuild the entire cluster from scratch on new hardware using S3 backups.

This is the most advanced scenario and involves a coordinated, two-phase process across all new nodes.

#### Prerequisites:

*   You have provisioned an entirely new set of machines for the cluster.
*   Puppet has run on all new nodes, but the `cassandra` service is **stopped on all of them**.
*   You know the hostnames of the *original* nodes that were backed up to S3.

#### Phase 1: Restore the Schema (Run on ONE Node Only)

The first step is to create the keyspaces and table structures in the new, empty cluster.

1.  Choose **one node** in the new cluster to be the "schema master".
2.  SSH into this node.
3.  Start the Cassandra service on this node **only**: `sudo systemctl start cassandra`. Wait for it to come up.
4.  Run the restore script in `--schema-only` mode. You need to specify the `--source-host` of one of your original backed-up nodes.
    ```bash
    # Download the schema from the latest full backup of an original node.
    sudo /usr/local/bin/cassandra-admin restore -- \
      --date "2026-01-22-10-00" \
      --source-host original-node-01.example.com \
      --schema-only
    ```
5.  The script will download `schema.cql` to `/tmp/schema_restore.cql`.
6.  Apply this schema to the new cluster using `cqlsh`:
    ```bash
    # Use the password you've configured in Hiera for the new cluster.
    cqlsh -u cassandra -p 'YourNewClusterPassword' --ssl -f /tmp/schema_restore.cql
    ```
7.  Verify the keyspaces and tables now exist: `cqlsh -e "DESCRIBE KEYSPACES;"`.
8.  **Crucially, stop the Cassandra service** on this "schema master" node: `sudo systemctl stop cassandra`. The entire new cluster should now be offline again, but with the correct schema created.

#### Phase 2: Restore Data (Rolling Restore, Node by Node)

Now, you will perform a full node restore on each new machine, one at a time.

1.  **For the first node:**
    *   SSH into the new node (e.g., `new-node-01`).
    *   Run the full restore, pointing it to the backup of its corresponding original node.
        ```bash
        sudo /usr/local/bin/cassandra-admin restore -- \
          --date "2026-01-22-10-00" \
          --source-host original-node-01.example.com \
          --full-restore \
          --yes
        ```
    *   The script will restore the data and start Cassandra. Wait for it to fully initialize and report `UN` in `nodetool status`. This node will become the first seed of the restored cluster.

2.  **For all subsequent nodes (one by one):**
    *   SSH into the next new node (e.g., `new-node-02`).
    *   Run the same command, but change the `--source-host` to its corresponding original node.
        ```bash
        sudo /usr/local/bin/cassandra-admin restore -- \
          --date "2026-01-22-10-00" \
          --source-host original-node-02.example.com \
          --full-restore \
          --yes
        ```
    *   The script will restore the data and start Cassandra. It will automatically detect the running seed node and join the cluster.
    *   Wait for this node to report `UN` status before proceeding to the next one.

3.  Repeat this process until all nodes in the new cluster have been restored and are online. Your cluster is now fully recovered.

---

### Restore Scenario 4: Recovering from Accidental Schema Changes

> **Use Case:** An operator accidentally ran a destructive `ALTER TABLE` or `DROP TABLE` command, but the data on disk is still intact.

The `schema.cql` file included in every full backup is your safety net.

1.  **Identify the last known-good backup** before the schema change occurred.
2.  **Download the schema file** from that backup set using the `--schema-only` mode:
    ```bash
    sudo /usr/local/bin/cassandra-admin restore -- \
      --date "2026-01-20-18-00" \
      --source-host cassandra-node-01.example.com \
      --schema-only
    ```
3.  This downloads the full schema to `/tmp/schema_restore.cql`.
4.  **Do not apply the whole file.** Instead, open it in a text editor (`less /tmp/schema_restore.cql`).
5.  Find the correct `CREATE TABLE` statement for the table that was altered or dropped.
6.  Copy that single statement and execute it in `cqlsh` to restore the table's structure.

---

## Production Readiness Guide

Having functional backups is the first step. Ensuring they are reliable and secure is the next.

### Automated Service Monitoring and Restart

This module uses the native capabilities of `systemd` to ensure the Cassandra service remains running. If the Cassandra process crashes or is terminated unexpectedly, `systemd` will automatically attempt to restart it.

*   **How it Works:** Puppet creates a `systemd` override file that configures `Restart=always` and `RestartSec=10`. This means `systemd` will always try to bring the service back up, waiting 10 seconds between attempts to prevent rapid-fire restart loops.
*   **Configuration:** You can customize this behavior in Hiera. For example, to disable it, set `profile_cassandra_pfpt::service_restart: 'no'`. See the Hiera reference for more details.
*   **Monitoring:** While this provides automatic recovery, it's still critical to have external alerting (e.g., via Prometheus) to notify you *when* a restart has occurred, as it often points to an underlying issue that needs investigation.

### Monitoring Backups and Alerting

A backup that fails silently is not a backup. The automated backup jobs run via `systemd` timers. You must monitor their status.

*   **Manual Checks:**
    *   Check the journal for the timer units: `journalctl -u cassandra-full-backup.service` and `journalctl -u cassandra-incremental-backup.service`.
    *   Check the dedicated backup logs: `/var/log/cassandra/full_backup.log` and `/var/log/cassandra/incremental_backup.log`.

*   **Automated Alerting (Recommended):**
    *   Integrate your monitoring system (e.g., Prometheus with `node_exporter`'s textfile collector, Datadog) to parse the output of the backup log files.
    *   **Create alerts that trigger if a backup log has not been updated in 24 hours or if it contains "ERROR".**

### Testing Your Disaster Recovery Plan (Fire Drills)

The only way to trust your backups is to test them regularly.

1.  **Schedule Quarterly Drills:** At least once per quarter, perform a full DR test.
2.  **Provision an Isolated Environment:** Spin up a new, temporary VPC with a small, isolated Cassandra cluster (e.g., 3 nodes).
3.  **Execute the DR Playbook:** Follow the "Full Cluster Restore (Cold Start DR)" scenario documented above to restore your production backup into this test environment.
4.  **Validate Data:** Once restored, run queries to verify that the data is consistent and accessible.
5.  **Document and Decommission:** Note any issues found during the drill and then tear down the test environment.

### Important Security and Cost Considerations

*   **Encryption Key Management:**
    *   The `backup_encryption_key` is the most critical secret. It should be managed in Hiera-eyaml.
    *   **Key Rotation:** To rotate the key, update the encrypted value in Hiera. Puppet will deploy the change. From that point on, **new backups** will use the new key.
    *   **IMPORTANT:** You must securely store **all old keys** that were used for previous backups. If you need to restore from a backup made a month ago, you will need the key that was active at that time.

*   **S3 Cost Management:**
    *   S3 costs can grow significantly over time.
    *   The backup script now automatically manages a lifecycle policy to expire objects after `s3_retention_period` days.
    *   For more advanced strategies, consider using **S3 Lifecycle Policies** on your backup bucket directly. A typical policy would be:
        *   Transition backups older than 30 days to a cheaper storage class (e.g., S3 Infrequent Access).
        *   Transition backups older than 90 days to archival storage (e.g., S3 Glacier Deep Archive).
        *   Permanently delete backups older than your retention policy (e.g., 1 year).

*   **Cross-Region Disaster Recovery:**
    *   To protect against a full AWS region failure, enable **S3 Cross-Region Replication** on your backup bucket to automatically copy backups to a secondary DR region.
    *   Be aware of the data transfer costs associated with both replication and a potential cross-region restore.

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
*   `profile_cassandra_pfpt::full_backup_schedule` (String): The `systemd` OnCalendar schedule for the automated full backup job. Default: `'*-*-* 02:00:00'` (Daily at 2am).
*   `profile_cassandra_pfpt::incremental_backup_schedule` (String): The `systemd` OnCalendar schedule for the automated incremental backup job. Default: `'*-*-* 0/4:00:00'` (Every 4 hours).
*   `profile_cassandra_pfpt::backup_encryption_key` (Sensitive[String]): The secret key used to encrypt all backup archives. **WARNING:** This has an insecure default value to prevent Puppet runs from failing. You **MUST** override this with a strong, unique secret in your production Hiera data. Default: `'MustBeChanged-ChangeMe-ChangeMe!!'`.
*   `profile_cassandra_pfpt::backup_backend` (String): The storage backend to use for uploads. Set to `'local'` to disable uploads. Default: `'s3'`.
*   `profile_cassandra_pfpt::backup_s3_bucket` (String): The name of the S3 bucket to use when `backup_backend` is `'s3'`. Defaults to a sanitized version of the cluster name.
*   `profile_cassandra_pfpt::s3_retention_period` (Integer): The number of days to keep backups in S3 before they are automatically deleted by a lifecycle policy. The policy is applied automatically by the backup script. Set to 0 to disable. Default: `15`.
*   `profile_cassandra_pfpt::clearsnapshot_keep_days` (Integer): The number of days to keep local snapshots on the node before they are automatically deleted. Set to 0 to disable. Default: `3`.
*   `profile_cassandra_pfpt::upload_streaming` (Boolean): Whether to use a direct streaming pipeline for backups (`true`) or a more robust method using temporary files (`false`). Streaming is faster but can hide errors. Default: `false`.
*   `profile_cassandra_pfpt::backup_parallelism` (Integer): The number of concurrent tables to process during backup or restore operations. Default: `4`.
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

---

## Puppet Agent Management

The base `cassandra_pfpt` component module includes logic to manage the Puppet agent itself by ensuring a scheduled run is in place via cron.

*   **Scheduled Runs:** By default, the Puppet agent will run twice per hour at a staggered minute.
*   **Maintenance Window:** The cron job will **not** run if a file exists at `/var/lib/puppet-disabled`. Creating this file is the standard way to temporarily disable Puppet runs.
*   **Configuration:** You can override the default schedule by setting the `profile_cassandra_pfpt::puppet_cron_schedule` key in Hiera to a standard 5-field cron string.
