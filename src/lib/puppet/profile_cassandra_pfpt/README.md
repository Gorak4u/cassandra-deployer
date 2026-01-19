# `profile_cassandra_pfpt`

## Table of Contents

1.  [Description](#description)
2.  [Setup - The basics of getting started with profile_cassandra_pfpt](#setup)
3.  [Usage - Configuration options and additional functionality](#usage)
4.  [Reference - An under-the-hood peek at what the module is doing](#reference)
5.  [Limitations - OS compatibility, etc.](#limitations)
6.  [Development - Guide for contributing to the module](#development)

## Description

This module provides a complete profile for deploying and managing an Apache Cassandra node. It acts as a wrapper around the `cassandra_pfpt` component module, providing all of its configuration data via Hiera lookups. This allows for a clean separation of logic (in the component module) from data (in Hiera).

## Setup

This profile is intended to be included by a role class. For example:

```puppet
class role_cassandra_pfpt {
  include profile_cassandra_pfpt
}
```

All configuration should be provided via your Hiera data source.

## Usage

This profile exposes all the parameters of the underlying `cassandra_pfpt` component module through Hiera.

### Enabling Automated Backups (DIY Method)

This profile includes a simple, cron-based backup system using a DIY script.

To enable daily backups, set the following in your Hiera data:

```yaml
profile_cassandra_pfpt::manage_backups: true
profile_cassandra_pfpt::backup_s3_bucket: 'my-cassandra-backup-bucket'
```

You can customize the schedule using `systemd` calendar event formats:

```yaml
# Run backup at 2 AM every day
profile_cassandra_pfpt::backup_schedule: '*-*-* 02:00:00'

# Run backup every Sunday at 3 AM
profile_cassandra_pfpt::backup_schedule: 'Sun *-*-* 03:00:00'
```

### Enabling the JMX Exporter

To enable the Prometheus JMX Exporter agent, set the following in Hiera:

```yaml
profile_cassandra_pfpt::manage_jmx_exporter: true
```

You can customize the version and port:

```yaml
profile_cassandra_pfpt::jmx_exporter_version: '0.20.0'
profile_cassandra_pfpt::jmx_exporter_port: 9404
```

### Managing Cassandra Roles

You can declaratively manage Cassandra user roles via Hiera. The configuration is a hash where each key is the role name.

**Hiera Example:**

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

### Basic Configuration Example

A minimal Hiera configuration for a single-node cluster might look like this:

```yaml
# profile_cassandra_pfpt/hiera.yaml
profile_cassandra_pfpt::cassandra_version: '4.1.3-1'
profile_cassandra_pfpt::java_version: '11'
profile_cassandra_pfpt::cluster_name: 'MyTestCluster'
profile_cassandra_pfpt::cassandra_password: 'secure_password_for_cassandra_user'

# Since seeds list is empty, node will seed from itself
```

### Multi-Node Cluster Configuration

For a multi-node cluster, you would define the seed nodes.

```yaml
# common.yaml
profile_cassandra_pfpt::seeds:
  - '10.0.1.10'
  - '10.0.1.11'
```

### Multi-Data-Center Replication

To handle system keyspace replication in a multi-DC setup, define the replication strategy in Hiera.

```yaml
# common.yaml
profile_cassandra_pfpt::system_keyspaces_replication:
  'dc1': 3
  'dc2': 3
```

## Reference

This profile directly includes the `cassandra_pfpt` class and passes parameters to it. For a full list of all available Hiera keys, see the `init.pp` manifest in this module. Each `lookup` call corresponds to a configurable Hiera key.

## Limitations

This profile is primarily tested and supported on Red Hat Enterprise Linux and its derivatives (like CentOS, Rocky Linux). Support for other operating systems may require adjustments.

## Development

This module is generated and managed by Firebase Studio. Direct pull requests are not the intended workflow.
