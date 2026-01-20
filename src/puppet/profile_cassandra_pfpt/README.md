# profile_cassandra_pfpt

This module is a Puppet profile that wraps the `cassandra_pfpt` component module. Its purpose is to provide configuration data to the component module via Hiera lookups.

## Description

This profile class defines the "what" for a Cassandra node. It looks up all the necessary parameters using `lookup()` and passes them to the `cassandra_pfpt` class. This separates the logic of *how* to manage Cassandra (the component module) from *what* configuration to apply (the profile).

## Usage

This class is typically included by a role class (`role_cassandra_pfpt`). You can customize the behavior of the Cassandra installation by setting values in your Hiera data.

## Hiera Configuration Example

To configure your Cassandra node, you would define values in your Hiera YAML files. For example, in `data/common.yaml` or a node-specific file:

```yaml
---
# profile_cassandra_pfpt class parameters
profile_cassandra_pfpt::cluster_name: 'My-Production-Cluster'
profile_cassandra_pfpt::datacenter: 'dc1'
profile_cassandra_pfpt::rack: 'rack1'

# --- Seed Node Configuration ---
# Define the seed nodes for the cluster
profile_cassandra_pfpt::seeds:
  - '10.0.1.10'
  - '10.0.1.11'
  - '10.0.1.12'

# --- JVM Settings ---
# Common JVM memory settings
profile_cassandra_pfpt::max_heap_size: '8G'
profile_cassandra_pfpt::gc_type: 'G1GC' # G1GC is recommended for C* 4.x

# Add any additional JVM options as a hash
profile_cassandra_pfpt::jvm_additional_opts:
  'cassandra.skip_wait_for_gossip_to_settle': '-1'
  'some.other.java.property': 'value'

# --- Backup Management ---
# Enable full backups to S3
profile_cassandra_pfpt::manage_full_backups: true
profile_cassandra_pfpt::backup_s3_bucket: 'my-cassandra-backups-bucket'
profile_cassandra_pfpt::backup_upload_streaming: true # Use streaming to save disk space

# Enable incremental backups (runs more frequently)
profile_cassandra_pfpt::manage_incremental_backups: true

# --- System & Monitoring ---
# Example of overriding sysctl settings
profile_cassandra_pfpt::sysctl_settings:
  vm.max_map_count: 1048576
  fs.aio-max-nr: 1048576

# Example of enabling the JMX Exporter for Prometheus monitoring
profile_cassandra_pfpt::manage_jmx_exporter: true
profile_cassandra_pfpt::jmx_exporter_port: 9404
```
