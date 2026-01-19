
export const backup_restore = `
## Backup and Restore

This profile provides a fully automated, S3-based backup solution using \`systemd\` timers and a collection of helper scripts. It also includes a powerful restore script to handle various recovery scenarios.

### Automated Backups

#### How It Works
1.  **Configuration:** You enable and configure backups through Hiera.
2.  **Puppet Setup:** Puppet creates \`systemd\` timer and service units on each Cassandra node.
3.  **Scheduling:** \`systemd\` automatically triggers the backup scripts based on the \`OnCalendar\` schedule you define.
4.  **Execution & Metadata Capture:** The scripts first generate a \`backup_manifest.json\` file containing critical metadata like the cluster name, node IP, datacenter, rack, and the node's token ranges. They then create a data snapshot, archive everything (data, schema, and manifest), and upload it to your specified S3 bucket.

#### Configuration Examples

##### Scenario 1: Full Backups Only (for Dev/Test)
This is ideal for development environments or clusters where a daily recovery point is sufficient.

\`\`\`yaml
# Hiera:
profile_cassandra_pfpt::manage_full_backups: true
profile_cassandra_pfpt::backup_s3_bucket: 'my-dev-cassandra-backups'
profile_cassandra_pfpt::full_backup_schedule: '*-*-* 02:00:00' # Daily at 2 AM
\`\`\`

##### Scenario 2: Both Full and Incremental Backups (Recommended for Production)
This is the most robust strategy, providing a daily full snapshot and frequent incremental backups for point-in-time recovery.

\`\`\`yaml
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
\`\`\`

##### Scenario 3: Incremental Backups with Multiple Schedules
You can define multiple schedules for incremental backups by providing an array of schedule strings.

\`\`\`yaml
# Hiera:
profile_cassandra_pfpt::manage_incremental_backups: true
profile_cassandra_pfpt::backup_s3_bucket: 'my-critical-cassandra-backups'
profile_cassandra_pfpt::incremental_backup_schedule:
  - '0 */2 * * *'      # Every 2 hours
  - '*/30 9-17 * * 1-5' # Every 30 minutes during business hours on weekdays
\`\`\`

#### Hiera Parameters for Backups

*   \`profile_cassandra_pfpt::incremental_backups\` (Boolean): **Required for incremental backups.** Enables Cassandra's built-in feature to create hard links to new SSTables. Default: \`false\`.
*   \`profile_cassandra_pfpt::manage_full_backups\` (Boolean): Enables the scheduled \`full-backup-to-s3.sh\` script. Default: \`false\`.
*   \`profile_cassandra_pfpt::manage_incremental_backups\` (Boolean): Enables the scheduled \`incremental-backup-to-s3.sh\` script. Default: \`false\`.
*   \`profile_cassandra_pfpt::full_backup_schedule\` (String): The \`systemd\` OnCalendar schedule for full snapshot backups. Default: \`'daily'\`.
*   \`profile_cassandra_pfpt::incremental_backup_schedule\` (String | Array[String]): The \`systemd\` OnCalendar schedule(s) for incremental backups. Default: \`'0 */4 * * *'\`.
*   \`profile_cassandra_pfpt::backup_s3_bucket\` (String): The name of the S3 bucket to upload backups to. Default: \`'puppet-cassandra-backups'\`.
*   \`profile_cassandra_pfpt::full_backup_log_file\` (String): Log file path for the full backup script. Default: \`'/var/log/cassandra/full_backup.log'\`.
*   \`profile_cassandra_pfpt::incremental_backup_log_file\` (String): Log file path for the incremental backup script. Default: \`'/var/log/cassandra/incremental_backup.log'\`.


### Restoring from a Backup

A \`restore-from-s3.sh\` script is placed in \`/usr/local/bin\` on each node to perform restores. This script supports three primary modes. Before taking any action, the script will first download and display the \`backup_manifest.json\` from the archive and require operator confirmation. This is a critical safety check to ensure you are restoring the correct data.

#### Mode 1: Full Node Restore (Destructive)
This mode is for recovering a completely failed node or for disaster recovery. It is a **destructive** operation.

**WARNING:** Running a full restore will **WIPE ALL CASSANDRA DATA** on the target node before restoring the backup.

##### Usage
1.  SSH into the node you want to restore.
2.  Identify the backup you want to restore. You need the full backup identifier (e.g., \`full_snapshot_20231027120000\`).
3.  Run the script with only the backup ID:
    \`\`\`bash
    sudo /usr/local/bin/restore-from-s3.sh <backup_identifier>
    \`\`\`
The script is intelligent: if it detects that the backup is from a different node (based on IP address), it will automatically configure the node to replace the old one, correctly assuming its identity and token ranges in the cluster.

#### Mode 2: Granular Restore (Keyspace or Table)
This mode is for recovering a specific table or an entire keyspace from a backup without affecting the rest of the cluster. It is a **non-destructive** operation that uses Cassandra's \`sstableloader\` tool to stream the backed-up data into the live cluster without downtime or affecting other data.

**Prerequisite:** The keyspace and table schema must already exist in the cluster before you can load data into it.

##### Usage
1.  SSH into any Cassandra node in the cluster.
2.  Identify the backup (full or incremental) that contains the data you want to restore.
3.  Run the script with the backup ID, keyspace name, and optionally the table name.

*   **To restore a single table:**
    \`\`\`bash
    sudo /usr/local/bin/restore-from-s3.sh <backup_id> <keyspace_name> <table_name>
    \`\`\`
*   **To restore an entire keyspace:**
    \`\`\`bash
    sudo /usr/local/bin/restore-from-s3.sh <backup_id> <keyspace_name>
    \`\`\`

#### Mode 3: Schema-Only Restore
This mode is the first step for a full cluster disaster recovery. It extracts the \`schema.cql\` file from a backup archive without touching the live node.

##### Usage
1.  SSH into one node of your new, empty cluster.
2.  Run the script with the \`--schema-only\` flag and a backup ID.
    \`\`\`bash
    sudo /usr/local/bin/restore-from-s3.sh --schema-only <backup_id>
    \`\`\`
3.  This extracts \`schema.cql\` to \`/tmp/schema.cql\`. You can then apply it to the cluster with \`cqlsh\`.

### Disaster Recovery: Restoring to a Brand New Cluster (Cold Start)

This procedure outlines how to restore a full cluster from S3 backups onto a set of brand-new machines where the old cluster is completely lost. The intelligent restore script automates the most complex parts of this process.

**The Strategy:** The script automatically detects if it's the first node being restored in an empty cluster.
-   **For the First Node:** It will use the \`initial_token\` property in \`cassandra.yaml\` to force the node to bootstrap with the correct identity and token ranges from the backup.
-   **For All Subsequent Nodes:** It will use the standard (and safer) \`-Dcassandra.replace_address_first_boot\` method to join the now-live cluster.

**Prerequisites:**
*   You have a set of full backups for each node from the old cluster in S3.
*   You have provisioned a new set of machines for the new cluster. Puppet should be applied, and the \`cassandra\` service should be stopped on all new nodes.

#### Step 1: Restore the Schema

The schema (definitions of keyspaces and tables) must be restored first.

1.  Choose **one node** in the new cluster to act as a temporary coordinator. Start the \`cassandra\` service on this node only. A single-node, empty cluster will form.
2.  SSH into that coordinator node.
3.  Choose a **full backup** from any of your old nodes to source the schema from. Run the \`restore-from-s3.sh\` script in schema-only mode:
    \`\`\`bash
    sudo /usr/local/bin/restore-from-s3.sh --schema-only <backup_id_of_any_old_node>
    \`\`\`
4.  This extracts \`schema.cql\` to \`/tmp/schema.cql\`. **Apply the schema to the new cluster:**
    \`\`\`bash
    cqlsh -u cassandra -p 'YourPassword' -f /tmp/schema.cql
    \`\`\`
5.  Once the schema is applied, **stop the cassandra service** on this coordinator node. The entire new cluster should now be offline.

#### Step 2: Perform a Rolling Restore of All Nodes

Now, simply restore each node, one at a time. The script handles the complexity.

1.  **On the first node** (e.g., \`new-cassandra-1.example.com\`):
    *   SSH into the node.
    *   Identify the backup ID of the old node it is replacing.
    *   Run the restore script in full restore mode:
        \`\`\`bash
        sudo /usr/local/bin/restore-from-s3.sh <backup_id_for_old_cassandra_1>
        \`\`\`
    *   The script will detect it's the first node, use \`initial_token\` to start, and wait for it to come online.

2.  **On the second node** (e.g., \`new-cassandra-2.example.com\`):
    *   Wait for the first node to be fully up (check with \`nodetool status\` from the first node).
    *   SSH into the second node.
    *   Run the restore script:
        \`\`\`bash
        sudo /usr/local/bin/restore-from-s3.sh <backup_id_for_old_cassandra_2>
        \`\`\`
    *   The script will detect a live seed node, so it will automatically use the \`replace_address\` method to join the cluster.

3.  **Repeat for all remaining nodes.** Continue the process, restoring one node at a time, until the entire cluster is back online.

Once all nodes have been restored, your cluster is fully recovered. The restore script automatically cleans up any temporary configuration changes (\`initial_token\` or \`replace_address\` flags) after each successful node start.
`.trim();
