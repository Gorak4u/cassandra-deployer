
export const readme = `
# \`profile_cassandra_pfpt\`

## Table of Contents

1.  [Description](#description)
2.  [Setup](#setup)
3.  [Usage Examples](#usage-examples)
4.  [Hiera Parameter Reference](#hiera-parameter-reference)
5.  [Limitations](#limitations)
6.  [Development](#development)

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

All configuration for the node should be provided via your Hiera data source (e.g., in your \`common.yaml\` or node-specific YAML files).

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

### Enabling Automated Backups (DIY Method)

To enable backups with separate schedules for full and incremental backups:

\`\`\`yaml
profile_cassandra_pfpt::manage_backups: true
profile_cassandra_pfpt::incremental_backups: true # IMPORTANT: This must be enabled in Cassandra itself
profile_cassandra_pfpt::backup_s3_bucket: 'my-cassandra-backup-bucket'

# Run a full snapshot backup daily at 2 AM
profile_cassandra_pfpt::full_backup_schedule: '*-*-* 02:00:00'

# Run an incremental backup every 4 hours
profile_cassandra_pfpt::incremental_backup_schedule: '0 */4 * * *'
\`\`\`

#### Backup Strategy: Full + Incremental

The DIY backup solution now uses two separate scripts and schedules to implement a robust, two-stage backup strategy.

1.  **Full Backups (`full-backup-to-s3.sh`):**
    *   **What it does:** Takes a full `nodetool snapshot`, archives the data and schema, uploads it to S3, and cleans up the snapshot from the local disk.
    *   **When it runs:** Governed by the `profile_cassandra_pfpt::full_backup_schedule`. This should be less frequent (e.g., daily). This provides a solid, complete recovery point.

2.  **Incremental Backups (`incremental-backup-to-s3.sh`):**
    *   **What it does:** Scans for any new incremental backup files (hard links) created by Cassandra since the last backup. It archives these files, uploads them to a separate prefix in S3, and then **deletes the source incremental files from the local disk**. This cleanup is critical to prevent disk space from filling up.
    *   **When it runs:** Governed by the `profile_cassandra_pfpt::incremental_backup_schedule`. This should be more frequent (e.g., hourly) to minimize potential data loss (RPO).

This combined strategy provides the benefits of a full snapshot for a solid recovery base, plus the incremental files needed for point-in-time recovery up to the moment of the last incremental backup.


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

### JMX & Monitoring

*   \`profile_cassandra_pfpt::manage_jmx_security\` (Boolean): Whether to manage and enable JMX authentication. Default: \`true\`.
*   \`profile_cassandra_pfpt::manage_jmx_exporter\` (Boolean): Whether to enable the Prometheus JMX Exporter agent. **Default: \`false\`**.
*   \`profile_cassandra_pfpt::jmx_exporter_port\` (Integer): The port for the JMX Exporter to listen on. Default: \`9404\`.
*   \`profile_cassandra_pfpt::jmx_exporter_version\` (String): The version of the JMX Exporter JAR to use. Default: \`'0.20.0'\`.

### Automated Backup (DIY Script)

*   \`profile_cassandra_pfpt::manage_backups\` (Boolean): Master switch to enable automated backups using the DIY script. Default: \`false\`.
*   \`profile_cassandra_pfpt::full_backup_schedule\` (String): The \`systemd\` OnCalendar schedule for full snapshot backups. Default: \`'daily'\`.
*   \`profile_cassandra_pfpt::incremental_backup_schedule\` (String): The \`systemd\` OnCalendar schedule for incremental backups. Default: \`'0 */4 * * *'\` (every 4 hours).
*   \`profile_cassandra_pfpt::backup_s3_bucket\` (String): The name of the S3 bucket to upload backups to. Default: \`'puppet-cassandra-backups'\`.

### Incremental Backups
*   \`profile_cassandra_pfpt::incremental_backups\` (Boolean): Set to \`true\` to enable Cassandra's built-in incremental backup feature. This is **required** for the incremental backup script to find any files.

#### How Incremental Backups Work
When you set \`profile_cassandra_pfpt::incremental_backups\` to \`true\`, you enable a powerful, low-overhead feature inside Cassandra. Here’s a breakdown of the process:

1.  **The Trigger:** Every time Cassandra writes data from memory (a Memtable) to a permanent file on disk (an SSTable), this feature is triggered.
2.  **The Mechanism (Hard Links):** Instead of copying the new SSTable, Cassandra creates a **hard link** to it. A hard link is a filesystem entry that points to the exact same data on the disk. This is extremely fast and consumes no extra disk space initially.
3.  **The Location:** These hard links are placed in a specific \`backups\` subdirectory inside each table's data directory. The exact path follows this structure:

    \`/path/to/data/<keyspace_name>/<table_name>-<uuid>/backups/\`

    For example, you would find them here:
    \`/var/lib/cassandra/data/my_app/users-a1b2c3d4.../backups/\`

**Strategy for Incremental Backups:**

Incremental backups are not a standalone solution. They are used with full snapshots for point-in-time recovery. The recovery process is:
1.  Restore the most recent full snapshot.
2.  Copy all incremental backup files created *after* that snapshot was taken into the table's data directory.
3.  Run \`nodetool refresh\` on the node to load the new data.

**Important Considerations:**
*   **Disk Space:** This feature can consume significant disk space over time. The provided `incremental-backup-to-s3.sh` script **deletes** the incremental files after a successful upload to manage this.

### System & OS Tuning

*   \`profile_cassandra_pfpt::disable_swap\` (Boolean): If true, will disable swap and comment it out in \`/etc/fstab\`. Default: \`true\`.
*   \`profile_cassandra_pfpt::sysctl_settings\` (Hash): A hash of kernel parameters to set in \`/etc/sysctl.d/99-cassandra.conf\`. Default: \`{ 'fs.aio-max-nr' => 1048576 }\`.
*   \`profile_cassandra_pfpt::limits_settings\` (Hash): A hash of user limits to set in \`/etc/security/limits.d/cassandra.conf\`. Default: \`{ 'memlock' => 'unlimited', 'nofile' => 100000, ... }\`.

### Package Management

*   \`profile_cassandra_pfpt::manage_repo\` (Boolean): Whether Puppet should manage the Cassandra YUM repository. Default: \`true\`.
*   \`profile_cassandra_pfpt::package_dependencies\` (Array[String]): An array of dependency packages to install. Default: \`['cyrus-sasl-plain', 'jemalloc', 'python3', 'numactl']\`.

## Limitations

This profile is primarily tested and supported on Red Hat Enterprise Linux and its derivatives (like CentOS, Rocky Linux). Support for other operating systems may require adjustments.

## Development

This module is generated and managed by Firebase Studio. Direct pull requests are not the intended workflow.
`.trim();
