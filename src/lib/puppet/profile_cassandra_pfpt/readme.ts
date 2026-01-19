
export const readme = `
# \`profile_cassandra_pfpt\`

## Table of Contents

1.  [Description](#description)
2.  [Setup](#setup)
3.  [Usage Examples](#usage-examples)
4.  [Hiera Parameter Reference](#hiera-parameter-reference)
5.  [Backup and Restore](#backup-and-restore)
    1.  [Automated Backups](#automated-backups)
    2.  [Restoring from a Backup](#restoring-from-a-backup)
    3.  [Disaster Recovery: Restoring to a Brand New Cluster (Cold Start)](#disaster-recovery-restoring-to-a-brand-new-cluster-cold-start)
6.  [Limitations](#limitations)
7.  [Development](#development)

## Description

This module provides a complete profile for deploying and managing an Apache Cassandra node. It acts as a wrapper around the \`cassandra_pfpt\` component module, providing all of its configuration data via Hiera lookups. This allows for a clean separation of logic (in the component module) from data (in Hiera).

## Setup

This profile is intended to be included by a role class. For example:

\`\`\`puppet
# In your role manifest (e.g., roles/manifests/cassandra.pp)
class role::cassandra {
  include profile_cassandra_pfpt
}
\`\`\`

All configuration for the node should be provided via your Hiera data source (e.g., in your \`common.yaml\` or node-specific YAML files). The backup scripts require the \`jq\` and \`awscli\` packages, which this profile will install by default.

## Usage Examples

### Basic Single-Node Cluster

A minimal Hiera configuration for a single-node cluster that seeds from itself.

\`\`\`yaml
# common.yaml
profile_cassandra_pfpt::cluster_name: 'MyTestCluster'
profile_cassandra_pfpt::cassandra_password: 'a-very-secure-password'
\`\`\`

### Multi-Node Cluster

For a multi-node cluster, you define the seed nodes for the cluster to use for bootstrapping.

\`\`\`yaml
# common.yaml
profile_cassandra_pfpt::seeds_list:
  - '10.0.1.10'
  - '10.0.1.11'
  - '10.0.1.12'
\`\`\`

### Managing Cassandra Roles

You can declaratively manage Cassandra user roles.

\`\`\`yaml
profile_cassandra_pfpt::cassandra_roles:
  'readonly_user':
    password: 'SafePassword123'
    is_superuser: false
    can_login: true
  'app_admin':
    password: 'AnotherSafePassword456'
    is_superuser: true
    can_login: true
\`\`\`

## Hiera Parameter Reference

This section documents every available Hiera key for this profile.

### Core Settings

*   \`profile_cassandra_pfpt::cassandra_version\` (String): The version of the Cassandra package to install. Default: \`'4.1.10-1'\`.
*   \`profile_cassandra_pfpt::java_version\` (String): The major version of Java to install (e.g., '8', '11'). Default: \`'11'\`.
*   \`profile_cassandra_pfpt::cluster_name\` (String): The name of the Cassandra cluster. Default: \`'pfpt-cassandra-cluster'\`.
*   \`profile_cassandra_pfpt::seeds_list\` (Array[String]): A list of seed node IP addresses. If empty, the node will seed from itself. Default: \`[]\`.
*   \`profile_cassandra_pfpt::cassandra_password\` (String): The password for the main \`cassandra\` superuser. Default: \`'PP#C@ss@ndr@000'\`.

### Topology

*   \`profile_cassandra_pfpt::datacenter\` (String): The name of the datacenter this node belongs to. Default: \`'dc1'\`.
*   \`profile_cassandra_pfpt::rack\` (String): The name of the rack this node belongs to. Default: \`'rack1'\`.
*   \`profile_cassandra_pfpt::endpoint_snitch\` (String): The snitch to use for determining network topology. Default: \`'GossipingPropertyFileSnitch'\`.
*   \`profile_cassandra_pfpt::racks\` (Hash): A hash for mapping racks to datacenters, used by \`GossipingPropertyFileSnitch\`. Default: \`{}\`.

### Networking

*   \`profile_cassandra_pfpt::listen_address\` (String): The IP address for Cassandra to listen on. Default: \`$facts['networking']['ip']\`.
*   \`profile_cassandra_pfpt::native_transport_port\` (Integer): The port for CQL clients. Default: \`9042\`.
*   \`profile_cassandra_pfpt::storage_port\` (Integer): The port for internode communication. Default: \`7000\`.
*   \`profile_cassandra_pfpt::ssl_storage_port\` (Integer): The port for SSL internode communication. Default: \`7001\`.
*   \`profile_cassandra_pfpt::rpc_port\` (Integer): The port for the Thrift RPC service. Default: \`9160\`.
*   \`profile_cassandra_pfpt::start_native_transport\` (Boolean): Whether to start the CQL native transport service. Default: \`true\`.
*   \`profile_cassandra_pfpt::start_rpc\` (Boolean): Whether to start the legacy Thrift RPC service. Default: \`true\`.

### Directories & Paths

*   \`profile_cassandra_pfpt::data_dir\` (String): Path to the data directories. Default: \`'/var/lib/cassandra/data'\`.
*   \`profile_cassandra_pfpt::commitlog_dir\` (String): Path to the commit log directory. Default: \`'/var/lib/cassandra/commitlog'\`.
*   \`profile_cassandra_pfpt::saved_caches_dir\` (String): Path to the saved caches directory. Default: \`'/var/lib/cassandra/saved_caches'\`.
*   \`profile_cassandra_pfpt::hints_directory\` (String): Path to the hints directory. Default: \`'/var/lib/cassandra/hints'\`.
*   \`profile_cassandra_pfpt::cdc_raw_directory\` (String): Path for Change Data Capture logs. Default: \`'/var/lib/cassandra/cdc_raw'\`.

### JVM & Performance

*   \`profile_cassandra_pfpt::max_heap_size\` (String): The maximum JVM heap size (e.g., '4G', '8000M'). Default: \`'3G'\`.
*   \`profile_cassandra_pfpt::gc_type\` (String): The garbage collector type to use ('G1GC' or 'CMS'). Default: \`'G1GC'\`.
*   \`profile_cassandra_pfpt::num_tokens\` (Integer): The number of tokens to assign to the node. Default: \`256\`.
*   \`profile_cassandra_pfpt::initial_token\` (String): For disaster recovery, specifies the comma-separated list of tokens for the first node being restored in a new cluster. Should be used with \`num_tokens: 1\`. Default: \`undef\`.
*   \`profile_cassandra_pfpt::concurrent_reads\` (Integer): The number of concurrent read requests. Default: \`32\`.
*   \`profile_cassandra_pfpt::concurrent_writes\` (Integer): The number of concurrent write requests. Default: \`32\`.
*   \`profile_cassandra_pfpt::concurrent_compactors\` (Integer): The number of concurrent compaction processes. Default: \`4\`.
*   \`profile_cassandra_pfpt::compaction_throughput_mb_per_sec\` (Integer): Throttles compaction to a specific throughput. Default: \`16\`.
*   \`profile_cassandra_pfpt::extra_jvm_args_override\` (Hash): A hash of extra JVM arguments to add or override in \`jvm-server.options\`. Default: \`{}\`.

### Security & Authentication

*   \`profile_cassandra_pfpt::authenticator\` (String): The authentication backend. Default: \`'PasswordAuthenticator'\`.
*   \`profile_cassandra_pfpt::authorizer\` (String): The authorization backend. Default: \`'CassandraAuthorizer'\`.
*   \`profile_cassandra_pfpt::role_manager\` (String): The role management backend. Default: \`'CassandraRoleManager'\`.
*   \`profile_cassandra_pfpt::cassandra_roles\` (Hash): A hash defining user roles to be managed declaratively. See example above. Default: \`{}\`.
*   \`profile_cassandra_pfpt::system_keyspaces_replication\` (Hash): Defines the replication factor for system keyspaces in a multi-DC setup. Example: \`{ 'dc1' => 3, 'dc2' => 3 }\`. Default: \`{}\`.

### TLS/SSL Encryption

*   \`profile_cassandra_pfpt::ssl_enabled\` (Boolean): Master switch to enable TLS/SSL encryption. Default: \`false\`.
*   \`profile_cassandra_pfpt::keystore_password\` (String): Password for the keystore. Default: \`'ChangeMe'\`.
*   \`profile_cassandra_pfpt::truststore_password\` (String): Password for the truststore. Default: \`'changeit'\`.
*   \`profile_cassandra_pfpt::internode_encryption\` (String): Encryption mode for server-to-server communication (\`all\`, \`none\`, \`dc\`, \`rack\`). Default: \`'all'\`.
*   Additional TLS parameters are available; see \`profile_cassandra_pfpt/manifests/init.pp\` for the full list.

### System & OS Tuning

*   \`profile_cassandra_pfpt::disable_swap\` (Boolean): If true, will disable swap and comment it out in \`/etc/fstab\`. Default: \`true\`.
*   \`profile_cassandra_pfpt::sysctl_settings\` (Hash): A hash of kernel parameters to set in \`/etc/sysctl.d/99-cassandra.conf\`. Default: \`{ 'fs.aio-max-nr' => 1048576 }\`.
*   \`profile_cassandra_pfpt::limits_settings\` (Hash): A hash of user limits to set in \`/etc/security/limits.d/cassandra.conf\`. Default: \`{ 'memlock' => 'unlimited', 'nofile' => 100000, ... }\`.

### Package Management

*   \`profile_cassandra_pfpt::manage_repo\` (Boolean): Whether Puppet should manage the Cassandra YUM repository. Default: \`true\`.
*   \`profile_cassandra_pfpt::package_dependencies\` (Array[String]): An array of dependency packages to install. Default: \`['cyrus-sasl-plain', 'jemalloc', 'python3', 'numactl', 'jq', 'awscli']\`.


## Backup and Restore

This profile provides a fully automated, S3-based backup solution using `systemd` timers and a collection of helper scripts. It also includes a powerful restore script to handle various recovery scenarios.

### Automated Backups

#### How It Works
1.  **Configuration:** You enable and configure backups through Hiera.
2.  **Puppet Setup:** Puppet creates `systemd` timer and service units on each Cassandra node.
3.  **Scheduling:** `systemd` automatically triggers the backup scripts based on the `OnCalendar` schedule you define.
4.  **Execution & Metadata Capture:** The scripts first generate a `backup_manifest.json` file containing critical metadata like the cluster name, node IP, datacenter, rack, and the node's token ranges. They then create a data snapshot, archive everything (data, schema, and manifest), and upload it to your specified S3 bucket.

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

*   \`profile_cassandra_pfpt::incremental_backups\` (Boolean): **Required for incremental backups.** Enables Cassandra's built-in feature to create hard links to new SSTables. Default: `false`.
*   \`profile_cassandra_pfpt::manage_full_backups\` (Boolean): Enables the scheduled `full-backup-to-s3.sh` script. Default: `false`.
*   \`profile_cassandra_pfpt::manage_incremental_backups\` (Boolean): Enables the scheduled `incremental-backup-to-s3.sh` script. Default: `false`.
*   \`profile_cassandra_pfpt::full_backup_schedule\` (String): The `systemd` OnCalendar schedule for full snapshot backups. Default: `'daily'`.
*   \`profile_cassandra_pfpt::incremental_backup_schedule\` (String | Array[String]): The `systemd` OnCalendar schedule(s) for incremental backups. Default: `'0 */4 * * *'`.
*   \`profile_cassandra_pfpt::backup_s3_bucket\` (String): The name of the S3 bucket to upload backups to. Default: `'puppet-cassandra-backups'`.
*   \`profile_cassandra_pfpt::full_backup_log_file\` (String): Log file path for the full backup script. Default: `'/var/log/cassandra/full_backup.log'`.
*   \`profile_cassandra_pfpt::incremental_backup_log_file\` (String): Log file path for the incremental backup script. Default: `'/var/log/cassandra/incremental_backup.log'`.


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

This procedure outlines how to restore a full cluster from S3 backups onto a set of brand-new machines where the old cluster is completely lost. This is the most complex recovery scenario.

**The Challenge:** When bootstrapping a brand-new cluster from backups, the first node has no other nodes to talk to. The standard \`-Dcassandra.replace_address_first_boot\` flag will not work because there is no existing cluster to join. The first node must be manually "forced" to start with the token ranges from its backup. Once this first node is live, all subsequent nodes can be restored using the simpler \`replace_address\` method.

**Prerequisites:**
*   You have a set of full backups for each node from the old cluster in S3.
*   You have provisioned a new set of machines for the new cluster, with Puppet applied but with Cassandra services potentially stopped.

#### Step 1: Restore the Schema
The schema (definitions of keyspaces and tables) must be restored first.

1.  Provision your new cluster with Puppet. A basic, empty Cassandra cluster should form.
2.  Choose **one node** in the new cluster to act as a temporary "coordinator" for the schema restore.
3.  SSH into that coordinator node.
4.  Choose a **full backup** from any of your old nodes to source the schema from. Run the \`restore-from-s3.sh\` script in schema-only mode:
    \`\`\`bash
    sudo /usr/local/bin/restore-from-s3.sh --schema-only <backup_id_of_any_old_node>
    \`\`\`
5.  This extracts \`schema.cql\` to \`/tmp/schema.cql\`. **Crucially, apply the schema to the new cluster.**
    \`\`\`bash
    cqlsh -u cassandra -p 'YourPassword' -f /tmp/schema.cql
    \`\`\`
    Once this command finishes, the schema is replicated across all nodes in the new, empty cluster.

#### Step 2: Restore the First Node (The "Seed" Restore)
This step uses the \`initial_token\` parameter to force the first node to adopt the identity of its backed-up counterpart.

1.  **Choose a "first node"** in your new cluster to restore. This node will become the seed for the restored cluster. Let's say you choose \`new-cassandra-1.example.com\`.
2.  **Find its corresponding backup.** Identify the backup ID for the old node that \`new-cassandra-1\` is replacing (e.g., \`old-cassandra-1\`). Run the \`restore-from-s3.sh\` script with the \`--schema-only\` flag just to safely view the manifest:
    \`\`\`bash
    sudo /usr/local/bin/restore-from-s3.sh --schema-only <backup_id_for_old_cassandra_1>
    \`\`\`
3.  From the manifest output, copy the **comma-separated list of tokens**.
4.  **Configure Hiera for the first node.** In your Hiera data for \`new-cassandra-1.example.com\`, set the following two parameters:
    \`\`\`yaml
    # In hiera data for new-cassandra-1.example.com
    profile_cassandra_pfpt::num_tokens: 1
    profile_cassandra_pfpt::initial_token: '<paste_the_comma_separated_tokens_here>'
    \`\`\`
5.  **Run Puppet** on \`new-cassandra-1.example.com\`. This will update its \`cassandra.yaml\` with the \`initial_token\` and \`num_tokens: 1\` settings.
6.  **Run the full restore** on \`new-cassandra-1.example.com\`:
    \`\`\`bash
    sudo /usr/local/bin/restore-from-s3.sh <backup_id_for_old_cassandra_1>
    \`\`\`
    The script will stop Cassandra, wipe the data, restore from the backup, and start Cassandra. Since \`initial_token\` is set, it will start up correctly with the old node's identity without needing to talk to other nodes.

#### Step 3: Restore Remaining Nodes
Once the first node is up and running (verify with \`nodetool status\`), you can restore the rest of the nodes using the standard, automated replacement process.

1.  **Revert Hiera changes.** Remove the \`num_tokens\` and \`initial_token\` overrides from Hiera for \`new-cassandra-1.example.com\`. Run Puppet again on that node to bring its configuration back to normal.
2.  For **each remaining node** (e.g., \`new-cassandra-2\`, \`new-cassandra-3\`, etc.):
    *   SSH into the node.
    *   Identify the backup ID of the old node it is replacing.
    *   Run the restore script in full restore mode:
        \`\`\`bash
        # On new-cassandra-2, run:
        sudo /usr/local/bin/restore-from-s3.sh <backup_id_for_old_cassandra_2>
        \`\`\`
    *   The script will automatically detect it's a DR scenario, use the \`-Dcassandra.replace_address_first_boot\` flag, connect to the already-restored first node, and correctly assume its identity and tokens.

Once all nodes have been restored, your cluster is fully recovered.

## Limitations

This profile is primarily tested and supported on Red Hat Enterprise Linux and its derivatives (like CentOS, Rocky Linux). Support for other operating systems may require adjustments.

## Development

This module is generated and managed by Firebase Studio. Direct pull requests are not the intended workflow.
`.trim();


