# Cassandra Backup & Recovery: A Complete Operations Guide

This document provides a complete, in-depth guide to the backup and recovery architecture for your Cassandra cluster. It is the single source of truth for all backup-related operations.

---

## Table of Contents

1.  [**Introduction & Philosophy**](#1-introduction--philosophy)
2.  [**Backup Architecture Deep Dive**](#2-backup-architecture-deep-dive)
    - [How Backups are Created](#how-backups-are-created)
    - [Backup Storage on S3](#backup-storage-on-s3)
    - [The Critical Role of the Manifest](#the-critical-role-of-the-manifest-backup_manifestjson)
    - [Schema Backups](#schema-backups-schemacql-and-schema_mappingjson)
    - [Encryption](#encryption)
3.  [**Automated Backups**](#3-automated-backups)
4.  [**Manual Operations: Backup & Status Checks**](#4-manual-operations-backup--status-checks)
5.  [**The Restore Process: Point-in-Time Recovery (PITR)**](#5-the-restore-process-point-in-time-recovery-pitr)
    - [The Restore Chain](#the-restore-chain)
    - [Previewing the Restore Chain](#previewing-the-restore-chain)
6.  [**Restore Scenarios: Step-by-Step Guides**](#6-restore-scenarios-step-by-step-guides)
    - [**Scenario 1: Granular Restore (Live Cluster)**](#scenario-1-granular-restore-live-cluster)
    - [**Scenario 2: Full Node Restore (Replacing a Single Failed Node)**](#scenario-2-full-node-restore-replacing-a-single-failed-node)
    - [**Scenario 3: Full Cluster Restore (Cold Start Disaster Recovery)**](#scenario-3-full-cluster-restore-cold-start-disaster-recovery)
    - [**Scenario 4: Recovering from Accidental Schema Changes**](#scenario-4-recovering-from-accidental-schema-changes)
7.  [**Production Readiness & Best Practices**](#7-production-readiness--best-practices)
    - [Monitoring Backups](#monitoring-backups)
    - [Disaster Recovery Drills](#disaster-recovery-drills-fire-drills)
    - [Security: Encryption Key Management](#security-encryption-key-management)
    - [Cost Management: S3 Lifecycle Policies](#cost-management-s3-lifecycle-policies)

---

## 1. Introduction & Philosophy

The backup system is designed around three core principles: **reliability, granularity, and recoverability**. We do not create single, large, monolithic backup files. Instead, we use a granular approach that enables powerful **Point-in-Time Recovery (PITR)**. All operations are managed through the unified `cass-ops` command-line tool.

## 2. Backup Architecture Deep Dive

### How Backups are Created

-   **Full Backups**: When a full backup is triggered (`cass-ops backup`), it first runs `nodetool snapshot`. This creates a hard link to every SSTable (data file) on the node. The script then iterates through every table, creating a separate, encrypted archive (`.tar.gz.enc`) for each one. This granular approach means we don't need massive amounts of temporary disk space for a single large archive.
-   **Incremental Backups**: When incremental backups are enabled in `cassandra.yaml`, Cassandra automatically creates a hard link in a `backups/` subdirectory for any SSTable that is flushed or compacted. The incremental backup job (`cass-ops incremental-backup`) simply archives and uploads the contents of these directories, then clears them out.

### Backup Storage on S3

All backups are stored in a structured path in your S3 bucket:

```
s3://<your-bucket-name>/<hostname>/<backup-timestamp>/
```

-   `<hostname>`: The hostname of the node that was backed up.
-   `<backup-timestamp>`: A timestamp in `YYYY-MM-DD-HH-MM` format that uniquely identifies a "Backup Set".

Inside a backup set directory, you will find the table archives and the critical manifest and schema files.

### The Critical Role of the Manifest (`backup_manifest.json`)

Every backup set contains a `backup_manifest.json`. **This file is the key to recovery.** It contains essential metadata:

-   `backup_type`: `full` or `incremental`.
-   `backup_id`: The timestamp of the backup set.
-   `source_node`:
    -   `ip_address`, `datacenter`, `rack`: The topology of the original node.
    -   `tokens`: The exact token ranges this node owned. This is **critical** for restoring a node's identity in the cluster.
-   `tables_backed_up`: A list or count of the tables included in the backup.

### Schema Backups (`schema.cql` and `schema_mapping.json`)

Full backups include two schema files:

-   `schema.cql`: A full dump of the database schema (`CREATE KEYSPACE`, `CREATE TABLE`, etc.) at the time of the backup. This is used for full cluster rebuilds.
-   `schema_mapping.json`: A JSON file that maps the human-readable table name (e.g., `my_app.users`) to its internal directory name, which is based on a UUID (e.g., `users-a1b2c3d4...`). This is **essential** for restores, as it allows the restore script to correctly place data even if the table has been dropped and recreated (which would change its UUID).

### Encryption

All data files are encrypted using **AES-256-CBC** before being uploaded to S3. The encryption key is specified in your Hiera configuration via `profile_cassandra_pfpt::backup_encryption_key`. **Losing this key means losing your backups.**

## 3. Automated Backups

-   **Scheduling**: Backups are managed by `cron`. Puppet configures jobs in `/etc/cron.d/` to run `cass-ops backup` (for full) and `cass-ops incremental-backup` on the schedules you define in Hiera.
-   **Logging**: All output is logged to `/var/log/cassandra/full_backup.log` and `/var/log/cassandra/incremental_backup.log`.
-   **Pausing**: To temporarily pause backups on a node for maintenance, create a flag file: `sudo touch /var/lib/backup-disabled`. Remove the file to re-enable them.

## 4. Manual Operations: Backup & Status Checks

-   **Trigger a Manual Full Backup**: `sudo cass-ops backup`
-   **Check Last Backup Status**: `sudo cass-ops backup-status`
-   **List All Backup Sets for a Host**: `sudo cass-ops restore --list-backups --source-host <hostname>`

## 5. The Restore Process: Point-in-Time Recovery (PITR)

The restore script is designed to bring your data back to a specific moment in time. The most important flag is `--date "YYYY-MM-DD-HH-MM"`.

### The Restore Chain

When you specify a target date, the script builds a "restore chain":

1.  It finds the most recent **full** backup that occurred *at or before* your target time. This is the restore's foundation.
2.  It then finds all **incremental** backups that occurred *between* that full backup and your target time.
3.  It presents this chain to you for confirmation before any data is downloaded.

### Previewing the Restore Chain

You can see exactly what files would be used for a restore without performing any action:

```bash
sudo cass-ops restore --show-restore-chain --date "2026-01-20-18-00"
```

## 6. Restore Scenarios: Step-by-Step Guides

---

### Scenario 1: Granular Restore (Live Cluster)

> **Use Case:** A specific table or keyspace was accidentally dropped, or data was corrupted. The rest of the cluster is healthy and online.

This is a **non-destructive** operation that streams data into a live, running cluster using `sstableloader`.

#### Steps:

1.  SSH into any Cassandra node in the cluster.
2.  Choose the appropriate restore action:
    -   `--download-and-restore`: Downloads the data and immediately loads it into the cluster.
    -   `--download-only`: Downloads and decrypts the data to `/var/lib/cassandra/restore_download/` for manual inspection. The data is **not** loaded.
3.  Execute the command with your target date and keyspace/table.

#### Example Commands:

```bash
# Example 1: Restore a single table ('users') to its state as of 6:00 PM on Jan 20, 2026.
sudo cass-ops restore \
  --date "2026-01-20-18-00" \
  --keyspace my_app \
  --table users \
  --download-and-restore

# Example 2: Restore an entire keyspace ('auditing').
sudo cass-ops restore \
  --date "2026-01-20-18-00" \
  --keyspace auditing \
  --download-and-restore
```
> **Note:** The script intelligently handles table UUID mismatches. If the live table has a different UUID than the backed-up data, it automatically renames the downloaded directory to match the live one before loading.

---

### Scenario 2: Full Node Restore (Replacing a Single Failed Node)

> **Use Case:** A node has suffered permanent hardware failure and must be replaced with a new machine.

This is a **destructive** operation performed on a **new, stopped node**.

#### Prerequisites:

-   A new machine has been provisioned.
-   Puppet has run successfully on the new machine.
-   The `cassandra` service is **stopped and disabled** on this new node.

#### Steps:

1.  SSH into the **new, stopped** node.
2.  Execute the restore script in `--full-restore` mode. You **must** use `--source-host` to specify the hostname of the *original, dead node* you are replacing.

    ```bash
    # Restore this new node using the backup data from 'cassandra-node-03.example.com'
    # to the point in time of the latest available backup.
    sudo cass-ops restore \
      --date "2026-01-22-10-00" \
      --source-host cassandra-node-03.example.com \
      --full-restore \
      --yes
    ```
3.  The script will automatically:
    -   Wipe any existing Cassandra data directories.
    -   Download the manifest from the dead node's backup to retrieve its unique ring tokens.
    -   Configure `cassandra.yaml` with these tokens, ensuring the new node assumes the correct identity.
    -   Download and extract the full data set from the backup chain.
    -   Move the data into the correct directories.
    -   Start the Cassandra service and verify it rejoins the cluster as `UN` (Up/Normal).

---

### Scenario 3: Full Cluster Restore (Cold Start Disaster Recovery)

> **Use Case:** A catastrophic failure has destroyed the entire cluster. You must rebuild from scratch on new hardware.

This is an advanced, coordinated, two-phase process.

#### Prerequisites:

-   An entirely new set of machines has been provisioned.
-   Puppet has run on all new nodes, but the `cassandra` service is **stopped and disabled on all of them**.
-   You know the hostnames of the *original* nodes that were backed up.

#### Phase 1: Restore the Schema (Run on ONE Node Only)

1.  Choose **one node** in the new cluster to be the "schema master".
2.  SSH into this node.
3.  Manually start the Cassandra service on this node **only**: `sudo systemctl start cassandra`.
4.  Run the restore script in `--schema-only` mode, pointing to the backup of one of your original nodes.

    ```bash
    sudo cass-ops restore \
      --date "2026-01-22-10-00" \
      --source-host original-node-01.example.com \
      --schema-only
    ```
5.  This downloads the schema to `/tmp/schema_restore.cql`.
6.  Apply this schema to the new cluster using `cqlsh`:

    ```bash
    cqlsh -u cassandra -p 'YourNewClusterPassword' --ssl -f /tmp/schema_restore.cql
    ```
7.  Verify the keyspaces exist: `cqlsh -e "DESCRIBE KEYSPACES;"`.
8.  **Crucially, stop the Cassandra service** on this "schema master" node: `sudo systemctl stop cassandra`.

#### Phase 2: Restore Data (Rolling, Node by Node)

Now, perform a **Full Node Restore (Scenario 2)** on each new machine.

> **CRITICAL:** You must perform this process sequentially, **one node at a time**. Wiping and restoring all nodes simultaneously and attempting to start them all at once is a common anti-pattern that can lead to a "split-brain" cluster, gossip failures, and an unstable state. The rolling approach ensures a clean and predictable cluster formation.

1.  **Restore the First Seed Node:**
    *   Choose one of your new nodes (ideally one that was a seed in the old cluster) to be the first seed of the new cluster.
    *   On this node, run the Scenario 2 `full-restore` command.
    *   **Wait for it to fully initialize and report `UN` in `nodetool status`**. This node is now the healthy seed for the new cluster. This may take several minutes.

2.  **Restore Remaining Nodes (Sequentially):**
    *   Move to the *next* new node.
    *   Run the same `full-restore` command on this node. It will restore its data and then use the first node as a seed to join the cluster.
    *   **Wait for this node to also report `UN` in `nodetool status` before proceeding to the next one.**
    *   Repeat this process for every remaining node in the cluster.

3.  **Verification:** Once all nodes are restored and report `UN`, the cluster recovery is complete. Run `nodetool status` on any node to verify that all nodes are present and healthy.

---

### Scenario 4: Recovering from Accidental Schema Changes

> **Use Case:** An `ALTER TABLE` or `DROP TABLE` command was run by mistake, but the data on disk is still intact.

1.  Identify the last known-good backup before the schema change occurred.
2.  Download the schema file from that backup using `--schema-only` mode:

    ```bash
    sudo cass-ops restore \
      --date "2026-01-20-18-00" \
      --source-host cassandra-node-01.example.com \
      --schema-only
    ```
3.  **Do not apply the whole file.** Open `/tmp/schema_restore.cql` in an editor.
4.  Find and copy the correct `CREATE TABLE` statement for the affected table.
5.  Execute just that single statement in `cqlsh` to restore the table's structure.

## 7. Production Readiness & Best Practices

### Monitoring Backups

-   Check the cron logs (`/var/log/cron` or `/var/log/syslog`) and the dedicated backup logs (`/var/log/cassandra/*.log`).
-   **Create alerts** in your monitoring system that trigger if a backup log has not been updated in 24 hours or if it contains the word "ERROR".

### Disaster Recovery Drills (Fire Drills)

The only way to trust your backups is to **test them regularly**. At least once a quarter, provision an isolated test environment and perform a full "Cold Start DR" (Scenario 3) to validate your backups and your process.

### Security: Encryption Key Management

-   The `backup_encryption_key` is your most critical secret. Manage it in Hiera-eyaml.
-   **Key Rotation:** To rotate the key, update the encrypted value in Hiera. **New backups** will use the new key.
-   **IMPORTANT:** You must securely store **all old keys** that were used for previous backups. To restore an old backup, you will need the key that was active at that time.

### Cost Management: S3 Lifecycle Policies

The backup script automatically sets a simple lifecycle policy on the S3 bucket to expire objects after the `s3_retention_period`. For more advanced strategies (e.g., moving old backups to Glacier), you can configure more complex policies directly on the S3 bucket in the AWS Console.
