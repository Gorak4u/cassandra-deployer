
export const puppetCode = {
  manifests: {
    'init.pp': `class profile_ggonda_cassandra (
  # Hiera-configurable parameters with defaults from puppetlabs-stdlib
  String $version              = '4.0.1',
  String $package_name         = 'cassandra',
  String $service_name         = 'cassandra',
  Stdlib::Absolutepath $config_file = '/etc/cassandra/cassandra.yaml',
  Stdlib::Absolutepath $env_file     = '/etc/cassandra/cassandra-env.sh',
  Optional[String] $java_package_name = undef,

  # cassandra.yaml parameters
  String $cluster_name = 'MyCassandraCluster',
  Array[String] $seeds = [\\\${facts['networking']['ip']}],
  String $listen_address = \\\${facts['networking']['ip']},
  String $rpc_address = \\\${facts['networking']['ip']},
  Array[Stdlib::Absolutepath] $data_file_directories = ['/var/lib/cassandra/data'],
  Stdlib::Absolutepath $commitlog_directory = '/var/lib/cassandra/commitlog',
) {
  # This makes the parameters available to other classes in the module
  # without having to pass them explicitly.
  contain profile_ggonda_cassandra::params

  # The main classes that compose the profile
  contain profile_ggonda_cassandra::java
  contain profile_ggonda_cassandra::install
  contain profile_ggonda_cassandra::config
  contain profile_ggonda_cassandra::service

  # Define the order of execution
  Class['profile_ggonda_cassandra::params']
  -> Class['profile_ggonda_cassandra::java']
  -> Class['profile_ggonda_cassandra::install']
  -> Class['profile_ggonda_cassandra::config']
  ~> Class['profile_ggonda_cassandra::service']
}`,
    'params.pp': `# @summary Sets up parameters for the Cassandra profile.
# This class pulls values from the main class, which are looked up in Hiera.
# No logic should be here, only parameter assignments for namespacing.
class profile_ggonda_cassandra::params {
  $version               = $profile_ggonda_cassandra::version
  $package_name          = $profile_ggonda_cassandra::package_name
  $service_name          = $profile_ggonda_cassandra::service_name
  $config_file           = $profile_ggonda_cassandra::config_file
  $env_file              = $profile_ggonda_cassandra::env_file
  $java_package_name     = $profile_ggonda_cassandra::java_package_name
  $cluster_name          = $profile_ggonda_cassandra::cluster_name
  $seeds                 = $profile_ggonda_cassandra::seeds
  $listen_address        = $profile_ggonda_cassandra::listen_address
  $rpc_address           = $profile_ggonda_cassandra::rpc_address
  $data_file_directories = $profile_ggonda_cassandra::data_file_directories
  $commitlog_directory   = $profile_ggonda_cassandra::commitlog_directory
}`,
    'java.pp': `# @summary Installs Java, a dependency for Cassandra.
class profile_ggonda_cassandra::java {
  $java_package_name = $profile_ggonda_cassandra::params::java_package_name

  # Determine the default Java package based on the OS family
  $default_java_package = $facts['os']['family'] ? {
    'RedHat' => 'java-1.8.0-openjdk-headless',
    'Debian' => 'openjdk-8-jre-headless',
    default  => fail("Unsupported OS family for Java installation: \\\${facts['os']['family']}"),
  }

  # Use the Hiera-provided package name if it exists, otherwise use the default
  $package_to_install = pick($java_package_name, $default_java_package)

  package { 'java-dependency':
    ensure => installed,
    name   => $package_to_install,
  }
}`,
    'install.pp': `# @summary Installs the Cassandra package.
class profile_ggonda_cassandra::install {
  $package_name = $profile_ggonda_cassandra::params::package_name
  $version = $profile_ggonda_cassandra::params::version

  # Extract major version for repo path, e.g., 4.0.1 -> 40
  $version_major = regsubst($version, '^(\\\\d)\\\\.(\\\\d)\\\\..*', '\\\\1\\\\2')

  # OS-specific installation logic
  case $facts['os']['family'] {
    'RedHat': {
      # For production, set gpgcheck to 1 and manage the key with a gpgkey resource
      yumrepo { 'cassandra':
        ensure   => 'present',
        descr    => "Apache Cassandra \\\${version_major}x repo",
        baseurl  => "https://downloads.apache.org/cassandra/redhat/\\\${version_major}x/",
        enabled  => 1,
        gpgcheck => 0,
      }
      # Define dependency chain
      Yumrepo['cassandra'] -> Package[$package_name]
    }
    'Debian': {
      # This requires the puppetlabs/apt module
      apt::source { 'cassandra':
        location => 'https://downloads.apache.org/cassandra/debian',
        release  => "\\\${version_major}x",
        repos    => 'main',
        # Key management is required for production
        # key      => { 'id' => '...', 'source' => '...' },
      }
      # Define dependency chain
      Apt::Source['cassandra'] -> Package[$package_name]
    }
    default: {
      fail("Cassandra installation is not supported on OS family '\\\${facts['os']['family']}'")
    }
  }

  package { $package_name:
    ensure  => $version,
    require => Class['profile_ggonda_cassandra::java'],
  }
}`,
    'config.pp': `# @summary Manages Cassandra configuration files.
class profile_ggonda_cassandra::config {
  $config_file = $profile_ggonda_cassandra::params::config_file
  $env_file    = $profile_ggonda_cassandra::params::env_file
  $owner       = 'cassandra'
  $group       = 'cassandra'

  # Create a string of seed nodes for the template
  $seeds_string = join($profile_ggonda_cassandra::params::seeds, ',')

  file { $config_file:
    ensure  => file,
    owner   => $owner,
    group   => $group,
    mode    => '0644',
    content => template('profile_ggonda_cassandra/cassandra.yaml.erb'),
    require => Package[$profile_ggonda_cassandra::params::package_name],
  }

  file { $env_file:
    ensure  => file,
    owner   => $owner,
    group   => $group,
    mode    => '0644',
    source  => 'puppet:///modules/profile_ggonda_cassandra/cassandra-env.sh',
    require => Package[$profile_ggonda_cassandra::params::package_name],
  }

  # Ensure data directories exist with correct permissions
  $profile_ggonda_cassandra::params::data_file_directories.each |String $dir| {
    file { $dir:
      ensure  => directory,
      owner   => $owner,
      group   => $group,
      mode    => '0750',
      require => Package[$profile_ggonda_cassandra::params::package_name],
    }
  }

  file { $profile_ggonda_cassandra::params::commitlog_directory:
    ensure  => directory,
    owner   => $owner,
    group   => $group,
    mode    => '0750',
    require => Package[$profile_ggonda_cassandra::params::package_name],
  }
}`,
    'service.pp': `# @summary Manages the Cassandra service.
class profile_ggonda_cassandra::service {
  $service_name = $profile_ggonda_cassandra::params::service_name

  service { $service_name:
    ensure    => running,
    enable    => true,
    hasstatus => true,
    # This service will restart whenever a subscribed resource changes.
    # It subscribes implicitly via the '~>' arrow in init.pp
  }
}`,
  },
  templates: {
    'cassandra.yaml.erb': `# cassandra.yaml
# Generated by Puppet from profile_ggonda_cassandra/cassandra.yaml.erb

cluster_name: '<%= @profile_ggonda_cassandra::params::cluster_name %>'
num_tokens: 256

# Seed provider
seed_provider:
  - class_name: org.apache.cassandra.locator.SimpleSeedProvider
    parameters:
      - seeds: "<%= @seeds_string %>"

listen_address: <%= @profile_ggonda_cassandra::params::listen_address %>
rpc_address: <%= @profile_ggonda_cassandra::params::rpc_address %>

# Snitch
endpoint_snitch: GossipingPropertyFileSnitch

# Data directories
data_file_directories:
<%- @profile_ggonda_cassandra::params::data_file_directories.each do |dir| -%>
  - <%= dir %>
<%- end -%>

commitlog_directory: <%= @profile_ggonda_cassandra::params::commitlog_directory %>

# Authentication and Authorization (commented out by default for security)
# authenticator: PasswordAuthenticator
# authorizer: CassandraAuthorizer
`,
  },
  files: {
    'cassandra-env.sh': `#!/bin/sh
# This file is managed by Puppet.
#
# Customize Cassandra environment variables here. For example, to set
# the JVM heap size, you could uncomment and adjust the following lines:
#
# MAX_HEAP_SIZE="4G"
# HEAP_NEWSIZE="800M"

# Other settings can be found in the default cassandra-env.sh file
# provided by the Cassandra package.
`,
  },
  scripts: {
    'backup.sh': `#!/bin/bash
# Example backup script for a Cassandra node.
# This is a very basic example and should be adapted for your environment.

# Variables
KEYSPACE="my_keyspace"
SNAPSHOT_NAME="snapshot_$(date +%Y-%m-%d_%H-%M-%S)"
BACKUP_DIR="/var/backups/cassandra/\\\${SNAPSHOT_NAME}"

echo "Creating snapshot \\\${SNAPSHOT_NAME} for keyspace \\\${KEYSPACE}..."

# Create the snapshot
nodetool snapshot -t "\\\${SNAPSHOT_NAME}" "\\\${KEYSPACE}"

if [ $? -ne 0 ]; then
  echo "Snapshot creation failed."
  exit 1
fi

echo "Snapshot created successfully."
echo "Copying snapshot files to \\\${BACKUP_DIR}..."

# Find and copy the snapshot files
# This logic will vary based on your Cassandra data directory structure
SNAPSHOT_PATH=$(find /var/lib/cassandra/data/\\\${KEYSPACE}/*/snapshots/\\\${SNAPSHOT_NAME} -type d | head -n 1)

mkdir -p "\\\${BACKUP_DIR}"
cp -r "\\\${SNAPSHOT_PATH}"/* "\\\${BACKUP_DIR}/"

if [ $? -ne 0 ]; then
  echo "Failed to copy snapshot files."
  # Consider clearing the snapshot here
  exit 1
fi

echo "Backup copied to \\\${BACKUP_DIR}."
echo "Clearing snapshot \\\${SNAPSHOT_NAME}..."

# Clear the snapshot
nodetool clearsnapshot -t "\\\${SNAPSHOT_NAME}" "\\\${KEYSPACE}"

echo "Backup complete."
`,
  },
};
