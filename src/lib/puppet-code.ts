
export const puppetCode = {
  cassandra_pfpt: {
    'metadata.json': `
{
  "name": "ggonda-cassandra_pfpt",
  "version": "1.0.0",
  "author": "ggonda",
  "summary": "Puppet component module to manage Apache Cassandra.",
  "license": "Apache-2.0",
  "source": "",
  "project_page": "",
  "issues_url": "",
  "dependencies": [],
  "operatingsystem_support": [
    { "operatingsystem": "RedHat", "operatingsystemrelease": [ "7", "8", "9" ] },
    { "operatingsystem": "CentOS", "operatingsystemrelease": [ "7", "8", "9" ] },
    { "operatingsystem": "Debian", "operatingsystemrelease": [ "9", "10", "11" ] },
    { "operatingsystem": "Ubuntu", "operatingsystemrelease": [ "18.04", "20.04", "22.04" ] }
  ],
  "requirements": [
    { "name": "puppet", "version_requirement": ">= 6.0.0 < 8.0.0" }
  ]
}
      `.trim(),
    manifests: {
      'init.pp': `
# @summary Main component class for managing Cassandra.
# This class orchestrates the installation, configuration, and service management.
class cassandra_pfpt (
  # Package and Service Parameters
  String $cassandra_version                 = '4.1.10-1',
  String $java_version                      = '11',
  String $java_package_version              = '',
  Boolean $manage_repo                       = true,
  String $user                               = 'cassandra',
  String $group                              = 'cassandra',
  String $repo_baseurl                       = "https://downloads.apache.org/cassandra/redhat/\${facts['os']['release']['major']}/",
  String $repo_gpgkey                        = 'https://downloads.apache.org/cassandra/KEYS',
  Array[String] $package_dependencies       = ['cyrus-sasl-plain', 'jemalloc'],

  # Configuration Parameters
  String $cluster_name                      = 'Production Cluster',
  String $seeds                             = $facts['networking']['ip'],
  String $listen_address                    = $facts['networking']['ip'],
  String $datacenter                        = 'dc1',
  String $rack                              = 'rack1',
  String $data_dir                          = '/var/lib/cassandra/data',
  String $commitlog_dir                     = '/var/lib/cassandra/commitlog',
  String $hints_directory                   = '/var/lib/cassandra/hints',
  String $max_heap_size                     = '4G',
  String $gc_type                           = 'G1GC',
  String $cassandra_password                = 'cassandra',
  String $replace_address                   = '',

  # OS Tuning Parameters
  Boolean $disable_swap                     = true,
  Hash $sysctl_settings                     = {},
  Hash $limits_settings                     = { 'nofile' => 100000, 'nproc' => 32768 },

  # Script and File Parameters
  String $manage_bin_dir                    = '/usr/local/bin',
  String $jamm_source                       = 'puppet:///modules/cassandra_pfpt/files/jamm-0.3.2.jar',
  String $jamm_target                       = '/usr/share/cassandra/lib/jamm-0.3.2.jar',

  # Service Management
  Boolean $enable_range_repair              = false
) {

  contain cassandra_pfpt::java
  contain cassandra_pfpt::install
  contain cassandra_pfpt::config
  contain cassandra_pfpt::service

  Class['cassandra_pfpt::java']
  -> Class['cassandra_pfpt::install']
  -> Class['cassandra_pfpt::config']
  ~> Class['cassandra_pfpt::service']
}
        `.trim(),
      'java.pp': `
# @summary Manages Java installation for Cassandra.
class cassandra_pfpt::java inherits cassandra_pfpt {
  $java_package_name = $facts['os']['family'] ? {
    'RedHat' => "java-\${java_version}-openjdk-headless",
    'Debian' => "openjdk-\${java_version}-jre-headless",
    default  => fail("Unsupported OS family for Java installation: \${facts['os']['family']}"),
  }

  $java_ensure_version = if $java_package_version and $java_package_version != '' {
    $java_package_version
  } else {
    'present'
  }

  package { $java_package_name:
    ensure  => $java_ensure_version,
  }
}
        `.trim(),
      'install.pp': `
# @summary Handles package installation for Cassandra and dependencies.
class cassandra_pfpt::install inherits cassandra_pfpt {

  user { $user:
    ensure     => 'present',
    system     => true,
  }

  group { $group:
    ensure => 'present',
    system => true,
  }

  if $manage_repo {
    if $facts['os']['family'] == 'RedHat' {
      yumrepo { 'cassandra':
        descr    => "Apache Cassandra \${cassandra_version} for EL\${facts['os']['release']['major']}",
        baseurl  => $repo_baseurl,
        gpgcheck => 1,
        enabled  => 1,
        gpgkey   => $repo_gpgkey,
        require  => Group[$group], # Ensure group exists before repo setup
      }
    }
  }

  package { $package_dependencies:
    ensure  => 'present',
    require => Class['cassandra_pfpt::java'],
  }

  package { 'cassandra':
    ensure  => $cassandra_version,
    require => [ Class['cassandra_pfpt::java'], User[$user] ],
  }

  package { 'cassandra-tools':
    ensure  => $cassandra_version,
    require => Package['cassandra'],
  }
}
        `.trim(),
      'config.pp': `
# @summary Manages Cassandra configuration files and OS tuning.
class cassandra_pfpt::config inherits cassandra_pfpt {
  file { [$data_dir, $commitlog_dir, $hints_directory]:
    ensure  => 'directory',
    owner   => $user,
    group   => $group,
    mode    => '0700',
  }

  file { '/root/.cassandra':
    ensure => 'directory',
    owner  => 'root',
    group  => 'root',
    mode   => '0700',
  }

  file { $jamm_target:
    ensure  => 'file',
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
    source  => $jamm_source,
  }

  file { '/etc/cassandra/conf/cassandra.yaml':
    ensure  => 'file',
    content => template('cassandra_pfpt/cassandra.yaml.erb'),
    owner   => $user,
    group   => $group,
    mode    => '0644',
  }

  file { '/etc/cassandra/conf/cassandra-rackdc.properties':
    ensure  => 'file',
    content => template('cassandra_pfpt/cassandra-rackdc.properties.erb'),
    owner   => $user,
    group   => $group,
    mode    => '0644',
  }

  file { '/etc/cassandra/conf/jvm-server.options':
    ensure  => 'file',
    content => template('cassandra_pfpt/jvm-server.options.erb'),
    owner   => $user,
    group   => $group,
    mode    => '0644',
  }

  file { '/root/.cassandra/cqlshrc':
    ensure  => 'file',
    content => template('cassandra_pfpt/cqlshrc.erb'),
    owner   => 'root',
    group   => 'root',
    mode    => '0600',
    require => File['/root/.cassandra'],
  }

  file { $manage_bin_dir:
    ensure => 'directory',
    owner  => 'root',
    group  => 'root',
    mode   => '0755',
  }

  [ 'cassandra-upgrade-precheck.sh', 'cluster-health.sh', 'repair-node.sh',
    'cleanup-node.sh', 'take-snapshot.sh', 'drain-node.sh', 'rebuild-node.sh',
    'garbage-collect.sh', 'assassinate-node.sh', 'upgrade-sstables.sh',
    'backup-to-s3.sh', 'prepare-replacement.sh', 'version-check.sh',
    'cassandra_range_repair.py', 'range-repair.sh', 'robust_backup.sh',
    'restore_from_backup.sh', 'node_health_check.sh', 'rolling_restart.sh' ].each |$script| {
    file { "\${manage_bin_dir}/\${script}":
      ensure  => 'file',
      source  => "puppet:///modules/cassandra_pfpt/scripts/\${script}",
      owner   => 'root',
      group   => 'root',
      mode    => '0755',
      require => File[$manage_bin_dir],
    }
  }

  if $disable_swap {
    exec { 'swapoff -a':
      command => '/sbin/swapoff -a',
      unless  => '/bin/cat /proc/swaps | /bin/grep -q "^/dev" -v',
      path    => ['/usr/bin', '/usr/sbin', '/bin', '/sbin'],
    }
    augeas { 'fstab_no_swap':
      context => '/files/etc/fstab',
      changes => 'set */[spec="swap"]/#comment "swap"',
      onlyif  => 'get */[spec="swap"] != ""',
      require => Exec['swapoff -a'],
    }
    $merged_sysctl = $sysctl_settings + { 'vm.swappiness' => 0 }
  } else {
    $merged_sysctl = $sysctl_settings
  }

  file { '/etc/sysctl.d/99-cassandra.conf':
    ensure  => 'file',
    content => epp('cassandra_pfpt/sysctl.conf.epp', { 'settings' => $merged_sysctl }),
    notify  => Exec['apply_sysctl_cassandra'],
  }

  exec { 'apply_sysctl_cassandra':
    command     => '/sbin/sysctl -p /etc/sysctl.d/99-cassandra.conf',
    path        => ['/usr/bin', '/usr/sbin', '/bin', '/sbin'],
    refreshonly => true,
  }

  file { '/etc/security/limits.d/cassandra.conf':
    ensure  => 'file',
    content => template('cassandra_pfpt/cassandra_limits.conf.erb'),
  }
}
        `.trim(),
      'service.pp': `
# @summary Manages the Cassandra service.
class cassandra_pfpt::service inherits cassandra_pfpt {
  service { 'cassandra':
    ensure     => running,
    enable     => true,
    hasstatus  => true,
    hasrestart => true,
  }

  $change_password_cql = '/root/change_password.cql'
  file { $change_password_cql:
    ensure  => file,
    content => "ALTER USER cassandra WITH PASSWORD '\${cassandra_password}';\\n",
    owner   => 'root',
    group   => 'root',
    mode    => '0600',
  }

  exec { 'change_cassandra_password':
    command   => "cqlsh -u cassandra -p cassandra -f \${change_password_cql}",
    path      => ['/bin/', '/usr/bin/'],
    tries     => 12,
    try_sleep => 10,
    unless    => "cqlsh -u cassandra -p '\${cassandra_password}' -e 'SELECT cluster_name FROM system.local;' \${listen_address} >/dev/null 2>&1",
    require   => Service['cassandra'],
  }

  if $enable_range_repair {
    file { '/etc/systemd/system/range-repair.service':
      ensure  => 'file',
      content => template('cassandra_pfpt/range-repair.service.erb'),
      owner   => 'root',
      group   => 'root',
      mode    => '0644',
      notify  => Exec['systemctl_daemon_reload_range_repair'],
    }

    exec { 'systemctl_daemon_reload_range_repair':
      command     => '/bin/systemctl daemon-reload',
      path        => ['/usr/bin', '/bin'],
      refreshonly => true,
    }

    service { 'range-repair':
      ensure    => 'running',
      enable    => true,
      hasstatus => true,
      subscribe => File['/etc/systemd/system/range-repair.service'],
    }
  }
}
        `.trim(),
      'firewall.pp': `
# @summary Placeholder for managing firewall rules for Cassandra.
class cassandra_pfpt::firewall {
  # This is a placeholder for firewall rules.
  # Implementation would go here, e.g., using puppetlabs/firewall module.
}
`.trim(),
    },
    templates: {
      'cassandra.yaml.erb': `
# cassandra.yaml
# Generated by Puppet from cassandra_pfpt/cassandra.yaml.erb.
cluster_name: '<%= @cluster_name %>'
num_tokens: 256
partitioner: org.apache.cassandra.dht.Murmur3Partitioner
data_file_directories:
    - '<%= @data_dir %>'
commitlog_directory: '<%= @commitlog_dir %>'
saved_caches_directory: /var/lib/cassandra/saved_caches
hints_directory: '<%= @hints_directory %>'
seed_provider:
    - class_name: org.apache.cassandra.locator.SimpleSeedProvider
      parameters:
          - seeds: "<%= @seeds %>"
listen_address: '<%= @listen_address %>'
rpc_address: '<%= @listen_address %>'
native_transport_port: 9042
endpoint_snitch: GossipingPropertyFileSnitch
authenticator: PasswordAuthenticator
authorizer: CassandraAuthorizer
# Add other cassandra.yaml settings here
        `.trim(),
      'cassandra-rackdc.properties.erb': `
# cassandra-rackdc.properties
# Generated by Puppet from cassandra_pfpt/cassandra-rackdc.properties.erb
dc=<%= @datacenter %>
rack=<%= @rack %>
        `.trim(),
      'jvm-server.options.erb': `
# jvm-server.options
# Generated by Puppet from cassandra_pfpt/jvm-server.options.erb
-Xms<%= @max_heap_size %>
-Xmx<%= @max_heap_size %>
<% if @gc_type == 'G1GC' %>
-XX:+UseG1GC
<% end %>
<% if @replace_address && !@replace_address.empty? %>
-Dcassandra.replace_address_first_boot=<%= @replace_address %>
<% end %>
# Add other JVM options here
        `.trim(),
      'cqlshrc.erb': `
# cqlshrc
# Generated by Puppet from cassandra_pfpt/cqlshrc.erb
[authentication]
username = cassandra
password = <%= @cassandra_password %>
[connection]
hostname = <%= @listen_address %>
port = 9042
        `.trim(),
      'range-repair.service.erb': `
[Unit]
Description=Cassandra Range Repair Service
[Service]
Type=simple
User=cassandra
Group=cassandra
ExecStart=/usr/local/bin/range-repair.sh
Restart=on-failure
[Install]
WantedBy=multi-user.target
        `.trim(),
      'cassandra_limits.conf.erb': `
# /etc/security/limits.d/cassandra.conf
# Generated by Puppet from cassandra_pfpt/cassandra_limits.conf.erb
<% @limits_settings.each do |limit, value| -%>
<%= @user %> - <%= limit %> <%= value %>
<% end -%>
        `.trim(),
      'sysctl.conf.epp': `
# /etc/sysctl.d/99-cassandra.conf
# Generated by Puppet from cassandra_pfpt/sysctl.conf.epp
<% $settings.each |$key, $value| -%>
<%= $key %> = <%= $value %>
<% end -%>
        `.trim(),
    },
    scripts: {
      'cassandra-upgrade-precheck.sh': '#!/bin/bash\n# Placeholder for cassandra-upgrade-precheck.sh\necho "Cassandra Upgrade Pre-check Script"',
      'cluster-health.sh': '#!/bin/bash\nnodetool status',
      'repair-node.sh': '#!/bin/bash\nnodetool repair -pr',
      'drain-node.sh': '#!/bin/bash\nnodetool drain',
      'cleanup-node.sh': '#!/bin/bash\necho "Cleanup Node Script"',
      'take-snapshot.sh': '#!/bin/bash\necho "Take Snapshot Script"',
      'rebuild-node.sh': '#!/bin/bash\necho "Rebuild Node Script"',
      'garbage-collect.sh': '#!/bin/bash\necho "Garbage Collect Script"',
      'assassinate-node.sh': '#!/bin/bash\necho "Assassinate Node Script"',
      'upgrade-sstables.sh': '#!/bin/bash\necho "Upgrade SSTables Script"',
      'backup-to-s3.sh': '#!/bin/bash\necho "Backup to S3 Script"',
      'prepare-replacement.sh': '#!/bin/bash\necho "Prepare Replacement Script"',
      'version-check.sh': '#!/bin/bash\necho "Version Check Script"',
      'cassandra_range_repair.py': '#!/usr/bin/env python3\nprint("Cassandra Range Repair Python Script")',
      'range-repair.sh': '#!/bin/bash\necho "Range Repair Script"',
      'robust_backup.sh': '#!/bin/bash\necho "Robust Backup Script Placeholder"',
      'restore_from_backup.sh': '#!/bin/bash\necho "Restore from Backup Script Placeholder"',
      'node_health_check.sh': '#!/bin/bash\necho "Node Health Check Script Placeholder"',
      'rolling_restart.sh': '#!/bin/bash\necho "Rolling Restart Script Placeholder"',
    },
    files: {
      'jamm-0.3.2.jar': '', // Placeholder for binary file
    },
  },
  profile_cassandra_pfpt: {
    'metadata.json': `
{
  "name": "ggonda-profile_cassandra_pfpt",
  "version": "1.0.0",
  "author": "ggonda",
  "summary": "Puppet profile for managing Cassandra.",
  "license": "Apache-2.0",
  "source": "",
  "project_page": "",
  "issues_url": "",
  "dependencies": [
    { "name": "ggonda-cassandra_pfpt", "version_requirement": ">= 1.0.0" }
  ],
  "operatingsystem_support": [
    { "operatingsystem": "RedHat", "operatingsystemrelease": [ "7", "8", "9" ] },
    { "operatingsystem": "CentOS", "operatingsystemrelease": [ "7", "8", "9" ] }
  ],
  "requirements": [
    { "name": "puppet", "version_requirement": ">= 6.0.0 < 8.0.0" }
  ]
}
      `.trim(),
    manifests: {
      'init.pp': `
# @summary Profile for configuring a Cassandra node.
# This class wraps the cassandra_pfpt component module and provides
# configuration data via Hiera.
class profile_cassandra_pfpt {
  # Hiera lookups with defaults
  $cassandra_version = lookup('profile_cassandra_pfpt::cassandra_version', { 'default_value' => '4.1.10-1' })
  $cluster_name      = lookup('profile_cassandra_pfpt::cluster_name', { 'default_value' => 'Production PFPT Cluster' })
  $seeds             = lookup('profile_cassandra_pfpt::seeds', { 'default_value' => $facts['networking']['ip'] })
  $datacenter        = lookup('profile_cassandra_pfpt::datacenter', { 'default_value' => 'dc1' })
  $rack              = lookup('profile_cassandra_pfpt::rack', { 'default_value' => 'rack1' })

  # Pass looked-up data to the component module
  class { 'cassandra_pfpt':
    cassandra_version => $cassandra_version,
    cluster_name      => $cluster_name,
    seeds             => $seeds,
    datacenter        => $datacenter,
    rack              => $rack,
    # All other parameters will use their defaults from the cassandra_pfpt class
  }
}
        `.trim(),
    },
  },
  role_cassandra_pfpt: {
    'metadata.json': `
{
  "name": "ggonda-role_cassandra_pfpt",
  "version": "1.0.0",
  "author": "ggonda",
  "summary": "Puppet role for a Cassandra server.",
  "license": "Apache-2.0",
  "source": "",
  "project_page": "",
  "issues_url": "",
  "dependencies": [
    { "name": "ggonda-profile_cassandra_pfpt", "version_requirement": ">= 1.0.0" }
  ],
  "operatingsystem_support": [
    { "operatingsystem": "RedHat", "operatingsystemrelease": [ "7", "8", "9" ] },
    { "operatingsystem": "CentOS", "operatingsystemrelease": [ "7", "8", "9" ] }
  ],
  "requirements": [
    { "name": "puppet", "version_requirement": ">= 6.0.0 < 8.0.0" }
  ]
}
      `.trim(),
    manifests: {
      'init.pp': `
# @summary Role class for a Cassandra node.
# This class defines the server's role by including the necessary profiles.
class role_cassandra_pfpt {
  # A Cassandra server is defined by the Cassandra profile.
  include profile_cassandra_pfpt
}
        `.trim(),
    },
  },
};
