
export const puppetCode = {
  cassandra_pfpt: {
    'metadata.json': `
{
  "name": "cassandra_pfpt",
  "version": "1.0.0",
  "author": "Puppet",
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
# This class is fully parameterized and should receive its data from a profile.
class cassandra_pfpt (
  String $cassandra_version,
  String $java_version,
  String $java_package_name,
  Boolean $manage_repo,
  String $user,
  String $group,
  String $repo_baseurl,
  String $repo_gpgkey,
  Array[String] $package_dependencies,
  String $cluster_name,
  String $seeds,
  String $listen_address,
  String $datacenter,
  String $rack,
  String $data_dir,
  String $commitlog_dir,
  String $hints_directory,
  String $max_heap_size,
  String $gc_type,
  String $cassandra_password,
  String $replace_address,
  Boolean $disable_swap,
  Hash $sysctl_settings,
  Hash $limits_settings,
  String $manage_bin_dir,
  String $jamm_source,
  String $jamm_target,
  Boolean $enable_range_repair,
  Boolean $use_java11,
  Boolean $use_g1_gc,
  Boolean $use_shenandoah_gc,
  Hash $racks,
  Boolean $ssl_enabled,
  String $target_dir,
  String $keystore_path,
  String $keystore_password,
  String $truststore_path,
  String $truststore_password,
  String $internode_encryption,
  Boolean $internode_require_client_auth,
  Boolean $client_optional,
  Boolean $client_require_client_auth,
  String $client_keystore_path,
  String $client_truststore_path,
  String $client_truststore_password,
  String $tls_protocol,
  String $tls_algorithm,
  String $store_type,
  Integer $concurrent_compactors,
  Integer $compaction_throughput_mb_per_sec,
  Integer $tombstone_warn_threshold,
  Integer $tombstone_failure_threshold,
  String $change_password_cql,
  String $cqlsh_path_env,
  Boolean $dynamic_snitch,
  Boolean $start_native_transport,
  String $role_manager,
  String $cdc_raw_directory,
  String $commit_failure_policy,
  String $commitlog_sync,
  String $disk_failure_policy,
  Boolean $incremental_backups,
  Integer $max_hints_delivery_threads,
  Boolean $native_transport_flush_in_batches_legacy,
  Integer $native_transport_max_frame_size_in_mb,
  Integer $range_request_timeout_in_ms,
  Integer $read_request_timeout_in_ms,
  Integer $request_timeout_in_ms,
  Integer $ssl_storage_port,
  Integer $storage_port,
  Integer $truncate_request_timeout_in_ms,
  Integer $write_request_timeout_in_ms,
  Integer $commitlog_sync_period_in_ms,
  Boolean $start_rpc,
  Integer $rpc_port,
  Boolean $rpc_keepalive,
  Integer $thrift_framed_transport_size_in_mb,
  Boolean $enable_transient_replication
) {

  contain cassandra_pfpt::java
  contain cassandra_pfpt::install
  contain cassandra_pfpt::config
  contain cassandra_pfpt::service
  contain cassandra_pfpt::firewall

  Class['cassandra_pfpt::java']
  -> Class['cassandra_pfpt::install']
  -> Class['cassandra_pfpt::config']
  ~> Class['cassandra_pfpt::service']
}
        `.trim(),
      'java.pp': `
# @summary Manages Java installation for Cassandra.
class cassandra_pfpt::java inherits cassandra_pfpt {
  $java_pkg_name = $facts['os']['family'] ? {
    'RedHat' => "java-\${java_version}-openjdk-headless",
    'Debian' => "openjdk-\${java_version}-jre-headless",
    default  => fail("Unsupported OS family for Java installation: \${facts['os']['family']}"),
  }

  $java_ensure_version = if $java_package_name and $java_package_name != '' {
    $java_package_name
  } else {
    'present'
  }

  package { $java_pkg_name:
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
  file { [$data_dir, $commitlog_dir, $hints_directory, $cdc_raw_directory]:
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
    content => template('cassandra_pfpt/sysctl.conf.erb'),
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

  file { $change_password_cql:
    ensure  => file,
    content => "ALTER USER cassandra WITH PASSWORD '\${cassandra_password}';\\n",
    owner   => 'root',
    group   => 'root',
    mode    => '0600',
  }

  exec { 'change_cassandra_password':
    command   => "cqlsh -u cassandra -p cassandra -f \${change_password_cql}",
    path      => ['/bin/', $cqlsh_path_env],
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
cluster_name: '<%= @cluster_name %>'
num_tokens: 256
partitioner: org.apache.cassandra.dht.Murmur3Partitioner

data_file_directories:
    - '<%= @data_dir %>'
commitlog_directory: '<%= @commitlog_dir %>'
saved_caches_directory: /var/lib/cassandra/saved_caches
hints_directory: '<%= @hints_directory %>'
cdc_raw_directory: '<%= @cdc_raw_directory %>'

seed_provider:
    - class_name: org.apache.cassandra.locator.SimpleSeedProvider
      parameters:
          - seeds: "<%= @seeds %>"

listen_address: '<%= @listen_address %>'
rpc_address: '<%= @listen_address %>'
native_transport_port: 9042
endpoint_snitch: GossipingPropertyFileSnitch
dynamic_snitch: <%= @dynamic_snitch %>
authenticator: PasswordAuthenticator
authorizer: CassandraAuthorizer
start_native_transport: <%= @start_native_transport %>
role_manager: <%= @role_manager %>
commit_failure_policy: <%= @commit_failure_policy %>
commitlog_sync: <%= @commitlog_sync %>
disk_failure_policy: <%= @disk_failure_policy %>
incremental_backups: <%= @incremental_backups %>
max_hints_delivery_threads: <%= @max_hints_delivery_threads %>
native_transport_flush_in_batches_legacy: <%= @native_transport_flush_in_batches_legacy %>
native_transport_max_frame_size_in_mb: <%= @native_transport_max_frame_size_in_mb %>
range_request_timeout_in_ms: <%= @range_request_timeout_in_ms %>
read_request_timeout_in_ms: <%= @read_request_timeout_in_ms %>
request_timeout_in_ms: <%= @request_timeout_in_ms %>
ssl_storage_port: <%= @ssl_storage_port %>
storage_port: <%= @storage_port %>
truncate_request_timeout_in_ms: <%= @truncate_request_timeout_in_ms %>
write_request_timeout_in_ms: <%= @write_request_timeout_in_ms %>
commitlog_sync_period_in_ms: <%= @commitlog_sync_period_in_ms %>

<% if @cassandra_version.start_with?('3.') -%>
start_rpc: <%= @start_rpc %>
rpc_port: <%= @rpc_port %>
rpc_keepalive: <%= @rpc_keepalive %>
thrift_framed_transport_size_in_mb: <%= @thrift_framed_transport_size_in_mb %>
<% else -%>
# Cassandra 4.x / 5.x specific settings
enable_transient_replication: <%= @enable_transient_replication %>
<% end -%>

<% if @ssl_enabled -%>
# --- Internode (node-to-node) encryption ---
server_encryption_options:
  internode_encryption: <%= @internode_encryption || 'all' %>  # 'none' | 'dc' | 'rack' | 'all'
  keystore: <%= @keystore_path || "#{@target_dir}/etc/keystore.jks" %>
  keystore_password: <%= @keystore_password %>
  # Set to true only if you want nodes to present client certs (mutual TLS for internode)
  require_client_auth: <%= @internode_require_client_auth ? 'true' : 'false' %>
  <% if @truststore_path && @truststore_password -%>
  truststore: <%= @truststore_path %>
  truststore_password: <%= @truststore_password %>
  <% end -%>
  <% if @tls_protocol -%>
  protocol: <%= @tls_protocol %>            # e.g., TLS
  <% end -%>
  <% if @tls_algorithm -%>
  algorithm: <%= @tls_algorithm %>          # e.g., SunX509
  <% end -%>
  <% if @store_type -%>
  store_type: <%= @store_type %>            # e.g., JKS
  <% end -%>

# --- Client (app-to-node) encryption ---
client_encryption_options: 
  enabled: true
  optional: <%= @client_optional ? 'true' : 'false' %> 
  keystore: <%= @client_keystore_path || "#{@target_dir}/etc/keystore.jks" %>
  keystore_password: <%= @keystore_password %>
<% end -%>
        `.trim(),
      'cassandra-rackdc.properties.erb': `
# cassandra-rackdc.properties
# Generated by Puppet from cassandra_pfpt/cassandra-rackdc.properties.erb
dc=<%= @datacenter %>
rack=<%= @rack %>
<% @racks.each do |r, dc| -%>
<%= r %>=<%= dc %>:<%= r.split('-')[-1] %>
<% end -%>
        `.trim(),
      'jvm-server.options.erb': `
# JVM configuration for Cassandra
-ea

-da:net.openhft...

# Heap size
-Xms<%= @max_heap_size %>
-Xmx<%= @max_heap_size %>

# GC type
<% if @gc_type == 'G1GC' %>
-XX:+UseG1GC
<% if @java_version.to_i < 14 %>
-XX:G1HeapRegionSize=16M
-XX:MaxGCPauseMillis=500
-XX:InitiatingHeapOccupancyPercent=75
-XX:+ParallelRefProcEnabled
-XX:+AggressiveOpts
<% end %>
<% elsif @gc_type == 'CMS' && @java_version.to_i < 14 %>
-XX:+UseConcMarkSweepGC
-XX:+CMSParallelRemarkEnabled
-XX:SurvivorRatio=8
-XX:MaxTenuringThreshold=1
-XX:CMSInitiatingOccupancyFraction=75
-XX:+UseCMSInitiatingOccupancyOnly
-XX:+CMSClassUnloadingEnabled
-XX:+AlwaysPreTouch
<% end %>

# GC logging
<% if @java_version.to_i >= 11 %>
-Xlog:gc*:/var/log/cassandra/gc.log:time,uptime,pid,tid,level,tags:filecount=10,filesize=100M
<% else %>
-Xloggc:/var/log/cassandra/gc.log
-XX:+PrintGCDetails
-XX:+PrintGCDateStamps
-XX:+PrintHeapAtGC
-XX:+PrintTenuringDistribution
-XX:+PrintGCApplicationStoppedTime
-XX:+UseGCLogFileRotation
-XX:NumberOfGCLogFiles=10
-XX:GCLogFileSize=100M
<% end %>

# Other common options
-Dcassandra.jmx.local.port=7199
-Djava.net.preferIPv4Stack=true
-Dcom.sun.management.jmxremote.port=7199
-Dcom.sun.management.jmxremote.rmi.port=7199
-Dcom.sun.management.jmxremote.ssl=false
-Dcom.sun.management.jmxremote.authenticate=false
-Dlogback.configurationFile=logback.xml
-Dlogback.defaultConfigurationFile=logback-default.xml

<% if @replace_address && !@replace_address.empty? %>
# Replace dead node at first boot (set by Hiera/Puppet)
-Dcassandra.replace_address_first_boot=<%= @replace_address %>
<% end %>
`.trim(),
      'cqlshrc.erb': `
# cqlshrc configuration file generated by Puppet

[authentication]
username = cassandra
password = <%= @cassandra_password %>

[connection]
hostname = <%= @listen_address %>
port = 9042

<% if @ssl_enabled %>
[ssl]
certfile =  <%= "#{@target_dir}/etc/keystore.pem" %>
version = SSLv23
validate = false
<% end %>
        `.trim(),
      'range-repair.service.erb': `
[Unit]
Description=Cassandra Range Repair Service
[Service]
Type=simple
User=cassandra
Group=cassandra
ExecStart=<%= @target_dir %>/range-repair.sh
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
      'sysctl.conf.erb': `
# /etc/sysctl.d/99-cassandra.conf
# Generated by Puppet from cassandra_pfpt/sysctl.conf.erb
<% @merged_sysctl.each do |key, value| -%>
<%= key %> = <%= value %>
<% end -%>
        `.trim(),
    },
    scripts: {
      'cassandra-upgrade-precheck.sh': '#!/bin/bash\\n# Placeholder for cassandra-upgrade-precheck.sh\\necho "Cassandra Upgrade Pre-check Script"',
      'cluster-health.sh': '#!/bin/bash\\nnodetool status',
      'repair-node.sh': '#!/bin/bash\\nnodetool repair -pr',
      'drain-node.sh': '#!/bin/bash\\nnodetool drain',
      'cleanup-node.sh': '#!/bin/bash\\necho "Cleanup Node Script"',
      'take-snapshot.sh': '#!/bin/bash\\necho "Take Snapshot Script"',
      'rebuild-node.sh': '#!/bin/bash\\necho "Rebuild Node Script"',
      'garbage-collect.sh': '#!/bin/bash\\necho "Garbage Collect Script"',
      'assassinate-node.sh': '#!/bin/bash\\necho "Assassinate Node Script"',
      'upgrade-sstables.sh': '#!/bin/bash\\necho "Upgrade SSTables Script"',
      'backup-to-s3.sh': '#!/bin/bash\\necho "Backup to S3 Script"',
      'prepare-replacement.sh': '#!/bin/bash\\necho "Prepare Replacement Script"',
      'version-check.sh': '#!/bin/bash\\necho "Version Check Script"',
      'cassandra_range_repair.py': '#!/usr/bin/env python3\\nprint("Cassandra Range Repair Python Script")',
      'range-repair.sh': '#!/bin/bash\\necho "Range Repair Script"',
      'robust_backup.sh': '#!/bin/bash\\necho "Robust Backup Script Placeholder"',
      'restore_from_backup.sh': '#!/bin/bash\\necho "Restore from Backup Script Placeholder"',
      'node_health_check.sh': '#!/bin/bash\\necho "Node Health Check Script Placeholder"',
      'rolling_restart.sh': '#!/bin/bash\\necho "Rolling Restart Script Placeholder"',
    },
    files: {
      'jamm-0.3.2.jar': '', // Placeholder for binary file
    },
  },
  profile_cassandra_pfpt: {
    'metadata.json': `
{
  "name": "profile_cassandra_pfpt",
  "version": "1.0.0",
  "author": "Puppet",
  "summary": "Puppet profile for managing Cassandra.",
  "license": "Apache-2.0",
  "source": "",
  "project_page": "",
  "issues_url": "",
  "dependencies": [
    { "name": "cassandra_pfpt", "version_requirement": ">= 1.0.0" }
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
  $cassandra_version                = lookup('profile_cassandra_pfpt::cassandra_version', { 'default_value' => '4.1.10-1' })
  $java_version                     = lookup('profile_cassandra_pfpt::java_version', { 'default_value' => '11' })
  $java_package_name                = lookup('profile_cassandra_pfpt::java_package_name', { 'default_value' => '' })
  $cluster_name                     = lookup('profile_cassandra_pfpt::cluster_name', { 'default_value' => 'Production Cluster' })
  $seeds                            = lookup('profile_cassandra_pfpt::seeds', { 'default_value' => $facts['networking']['ip'] })
  $listen_address                   = lookup('profile_cassandra_pfpt::listen_address', { 'default_value' => $facts['networking']['ip'] })
  $use_java11                       = lookup('profile_cassandra_pfpt::use_java11', { 'default_value' => true })
  $use_g1_gc                        = lookup('profile_cassandra_pfpt::use_g1_gc', { 'default_value' => true })
  $use_shenandoah_gc                = lookup('profile_cassandra_pfpt::use_shenandoah_gc', { 'default_value' => false })
  $racks                            = lookup('profile_cassandra_pfpt::racks', { 'default_value' => {} })
  $datacenter                       = lookup('profile_cassandra_pfpt::datacenter', { 'default_value' => 'dc1' })
  $rack                             = lookup('profile_cassandra_pfpt::rack', { 'default_value' => 'rack1' })
  $cassandra_password               = lookup('profile_cassandra_pfpt::cassandra_password', { 'default_value' => 'cassandra' })
  $max_heap_size                    = lookup('profile_cassandra_pfpt::max_heap_size', { 'default_value' => '4G' })
  $gc_type                          = lookup('profile_cassandra_pfpt::gc_type', { 'default_value' => 'G1GC' })
  $data_dir                         = lookup('profile_cassandra_pfpt::data_dir', { 'default_value' => '/var/lib/cassandra/data' })
  $commitlog_dir                    = lookup('profile_cassandra_pfpt::commitlog_dir', { 'default_value' => '/var/lib/cassandra/commitlog' })
  $hints_directory                  = lookup('profile_cassandra_pfpt::hints_directory', { 'default_value' => '/var/lib/cassandra/hints' })
  $disable_swap                     = lookup('profile_cassandra_pfpt::disable_swap', { 'default_value' => true })
  $replace_address                  = lookup('profile_cassandra_pfpt::replace_address', { 'default_value' => '' })
  $enable_range_repair              = lookup('profile_cassandra_pfpt::enable_range_repair', { 'default_value' => false })
  $ssl_enabled                      = lookup('profile_cassandra_pfpt::ssl_enabled', { 'default_value' => false })
  $target_dir                       = lookup('profile_cassandra_pfpt::target_dir', { 'default_value' => '/usr/local/bin' })
  $keystore_path                    = lookup('profile_cassandra_pfpt::keystore_path', { 'default_value' => '/etc/cassandra/keystore.jks' })
  $keystore_password                = lookup('profile_cassandra_pfpt::keystore_password', { 'default_value' => 'cassandra' })
  $truststore_path                  = lookup('profile_cassandra_pfpt::truststore_path', { 'default_value' => '/etc/cassandra/truststore.jks' })
  $truststore_password              = lookup('profile_cassandra_pfpt::truststore_password', { 'default_value' => 'cassandra' })
  $internode_encryption             = lookup('profile_cassandra_pfpt::internode_encryption', { 'default_value' => 'all' })
  $internode_require_client_auth    = lookup('profile_cassandra_pfpt::internode_require_client_auth', { 'default_value' => true })
  $client_optional                  = lookup('profile_cassandra_pfpt::client_optional', { 'default_value' => false })
  $client_require_client_auth       = lookup('profile_cassandra_pfpt::client_require_client_auth', { 'default_value' => false })
  $client_keystore_path             = lookup('profile_cassandra_pfpt::client_keystore_path', { 'default_value' => '/etc/cassandra/keystore.jks' })
  $client_truststore_path           = lookup('profile_cassandra_pfpt::client_truststore_path', { 'default_value' => '/etc/cassandra/truststore.jks' })
  $client_truststore_password       = lookup('profile_cassandra_pfpt::client_truststore_password', { 'default_value' => 'cassandra' })
  $tls_protocol                     = lookup('profile_cassandra_pfpt::tls_protocol', { 'default_value' => 'TLS' })
  $tls_algorithm                    = lookup('profile_cassandra_pfpt::tls_algorithm', { 'default_value' => 'SunX509' })
  $store_type                       = lookup('profile_cassandra_pfpt::store_type', { 'default_value' => 'JKS' })
  $concurrent_compactors            = lookup('profile_cassandra_pfpt::concurrent_compactors', { 'default_value' => 4 })
  $compaction_throughput_mb_per_sec = lookup('profile_cassandra_pfpt::compaction_throughput_mb_per_sec', { 'default_value' => 16 })
  $tombstone_warn_threshold         = lookup('profile_cassandra_pfpt::tombstone_warn_threshold', { 'default_value' => 1000 })
  $tombstone_failure_threshold      = lookup('profile_cassandra_pfpt::tombstone_failure_threshold', { 'default_value' => 100000 })
  $sysctl_settings                  = lookup('profile_cassandra_pfpt::sysctl_settings', { 'default_value' => {} })
  $limits_settings                  = lookup('profile_cassandra_pfpt::limits_settings', { 'default_value' => { 'nofile' => 100000, 'nproc' => 32768 } })
  $manage_repo                      = lookup('profile_cassandra_pfpt::manage_repo', { 'default_value' => true })
  $user                             = lookup('profile_cassandra_pfpt::user', { 'default_value' => 'cassandra' })
  $group                            = lookup('profile_cassandra_pfpt::group', { 'default_value' => 'cassandra' })
  $repo_baseurl                     = lookup('profile_cassandra_pfpt::repo_baseurl', { 'default_value' => "https://downloads.apache.org/cassandra/redhat/\${facts['os']['release']['major']}/" })
  $repo_gpgkey                      = lookup('profile_cassandra_pfpt::repo_gpgkey', { 'default_value' => 'https://downloads.apache.org/cassandra/KEYS' })
  $package_dependencies             = lookup('profile_cassandra_pfpt::package_dependencies', { 'default_value' => ['cyrus-sasl-plain', 'jemalloc'] })
  $manage_bin_dir                   = lookup('profile_cassandra_pfpt::manage_bin_dir', { 'default_value' => '/usr/local/bin' })
  $change_password_cql              = lookup('profile_cassandra_pfpt::change_password_cql', { 'default_value' => '/root/change_password.cql' })
  $cqlsh_path_env                   = lookup('profile_cassandra_pfpt::cqlsh_path_env', { 'default_value' => '/usr/bin/' })
  $jamm_target                      = lookup('profile_cassandra_pfpt::jamm_target', { 'default_value' => '/usr/share/cassandra/lib/jamm-0.3.2.jar' })
  $jamm_source                      = lookup('profile_cassandra_pfpt::jamm_source', { 'default_value' => 'puppet:///modules/cassandra_pfpt/files/jamm-0.3.2.jar' })
  $dynamic_snitch                   = lookup('profile_cassandra_pfpt::dynamic_snitch', { 'default_value' => true })
  $start_native_transport           = lookup('profile_cassandra_pfpt::start_native_transport', { 'default_value' => true })
  $role_manager                     = lookup('profile_cassandra_pfpt::role_manager', { 'default_value' => 'CassandraRoleManager' })
  $cdc_raw_directory                = lookup('profile_cassandra_pfpt::cdc_raw_directory', { 'default_value' => '/var/lib/cassandra/cdc_raw' })
  $commit_failure_policy            = lookup('profile_cassandra_pfpt::commit_failure_policy', { 'default_value' => 'stop' })
  $commitlog_sync                   = lookup('profile_cassandra_pfpt::commitlog_sync', { 'default_value' => 'periodic' })
  $disk_failure_policy              = lookup('profile_cassandra_pfpt::disk_failure_policy', { 'default_value' => 'stop' })
  $incremental_backups              = lookup('profile_cassandra_pfpt::incremental_backups', { 'default_value' => false })
  $max_hints_delivery_threads       = lookup('profile_cassandra_pfpt::max_hints_delivery_threads', { 'default_value' => 2 })
  $native_transport_flush_in_batches_legacy = lookup('profile_cassandra_pfpt::native_transport_flush_in_batches_legacy', { 'default_value' => false })
  $native_transport_max_frame_size_in_mb    = lookup('profile_cassandra_pfpt::native_transport_max_frame_size_in_mb', { 'default_value' => 128 })
  $range_request_timeout_in_ms      = lookup('profile_cassandra_pfpt::range_request_timeout_in_ms', { 'default_value' => 10000 })
  $read_request_timeout_in_ms       = lookup('profile_cassandra_pfpt::read_request_timeout_in_ms', { 'default_value' => 5000 })
  $request_timeout_in_ms            = lookup('profile_cassandra_pfpt::request_timeout_in_ms', { 'default_value' => 10000 })
  $ssl_storage_port                 = lookup('profile_cassandra_pfpt::ssl_storage_port', { 'default_value' => 7001 })
  $storage_port                     = lookup('profile_cassandra_pfpt::storage_port', { 'default_value' => 7000 })
  $truncate_request_timeout_in_ms   = lookup('profile_cassandra_pfpt::truncate_request_timeout_in_ms', { 'default_value' => 60000 })
  $write_request_timeout_in_ms      = lookup('profile_cassandra_pfpt::write_request_timeout_in_ms', { 'default_value' => 10000 })
  $commitlog_sync_period_in_ms      = lookup('profile_cassandra_pfpt::commitlog_sync_period_in_ms', { 'default_value' => 10000 })
  $start_rpc                        = lookup('profile_cassandra_pfpt::start_rpc', { 'default_value' => true })
  $rpc_port                         = lookup('profile_cassandra_pfpt::rpc_port', { 'default_value' => 9160 })
  $rpc_keepalive                    = lookup('profile_cassandra_pfpt::rpc_keepalive', { 'default_value' => true })
  $thrift_framed_transport_size_in_mb = lookup('profile_cassandra_pfpt::thrift_framed_transport_size_in_mb', { 'default_value' => 15 })
  $enable_transient_replication     = lookup('profile_cassandra_pfpt::enable_transient_replication', { 'default_value' => false })

  class { 'cassandra_pfpt':
    cassandra_version                => $cassandra_version,
    java_version                     => $java_version,
    java_package_name                => $java_package_name,
    manage_repo                      => $manage_repo,
    user                             => $user,
    group                            => $group,
    repo_baseurl                     => $repo_baseurl,
    repo_gpgkey                      => $repo_gpgkey,
    package_dependencies             => $package_dependencies,
    cluster_name                     => $cluster_name,
    seeds                            => $seeds,
    listen_address                   => $listen_address,
    datacenter                       => $datacenter,
    rack                             => $rack,
    data_dir                         => $data_dir,
    commitlog_dir                    => $commitlog_dir,
    hints_directory                  => $hints_directory,
    max_heap_size                    => $max_heap_size,
    gc_type                          => $gc_type,
    cassandra_password               => $cassandra_password,
    replace_address                  => $replace_address,
    disable_swap                     => $disable_swap,
    sysctl_settings                  => $sysctl_settings,
    limits_settings                  => $limits_settings,
    manage_bin_dir                   => $manage_bin_dir,
    jamm_source                      => $jamm_source,
    jamm_target                      => $jamm_target,
    enable_range_repair              => $enable_range_repair,
    use_java11                       => $use_java11,
    use_g1_gc                        => $use_g1_gc,
    use_shenandoah_gc                => $use_shenandoah_gc,
    racks                            => $racks,
    ssl_enabled                      => $ssl_enabled,
    target_dir                       => $target_dir,
    keystore_path                    => $keystore_path,
    keystore_password                => $keystore_password,
    truststore_path                  => $truststore_path,
    truststore_password              => $truststore_password,
    internode_encryption             => $internode_encryption,
    internode_require_client_auth    => $internode_require_client_auth,
    client_optional                  => $client_optional,
    client_require_client_auth       => $client_require_client_auth,
    client_keystore_path             => $client_keystore_path,
    client_truststore_path           => $client_truststore_path,
    client_truststore_password       => $client_truststore_password,
    tls_protocol                     => $tls_protocol,
    tls_algorithm                    => $tls_algorithm,
    store_type                       => $store_type,
    concurrent_compactors            => $concurrent_compactors,
    compaction_throughput_mb_per_sec => $compaction_throughput_mb_per_sec,
    tombstone_warn_threshold         => $tombstone_warn_threshold,
    tombstone_failure_threshold      => $tombstone_failure_threshold,
    change_password_cql              => $change_password_cql,
    cqlsh_path_env                   => $cqlsh_path_env,
    dynamic_snitch                   => $dynamic_snitch,
    start_native_transport           => $start_native_transport,
    role_manager                     => $role_manager,
    cdc_raw_directory                => $cdc_raw_directory,
    commit_failure_policy            => $commit_failure_policy,
    commitlog_sync                   => $commitlog_sync,
    disk_failure_policy              => $disk_failure_policy,
    incremental_backups              => $incremental_backups,
    max_hints_delivery_threads       => $max_hints_delivery_threads,
    native_transport_flush_in_batches_legacy => $native_transport_flush_in_batches_legacy,
    native_transport_max_frame_size_in_mb    => $native_transport_max_frame_size_in_mb,
    range_request_timeout_in_ms      => $range_request_timeout_in_ms,
    read_request_timeout_in_ms       => $read_request_timeout_in_ms,
    request_timeout_in_ms            => $request_timeout_in_ms,
    ssl_storage_port                 => $ssl_storage_port,
    storage_port                     => $storage_port,
    truncate_request_timeout_in_ms   => $truncate_request_timeout_in_ms,
    write_request_timeout_in_ms      => $write_request_timeout_in_ms,
    commitlog_sync_period_in_ms      => $commitlog_sync_period_in_ms,
    start_rpc                        => $start_rpc,
    rpc_port                         => $rpc_port,
    rpc_keepalive                    => $rpc_keepalive,
    thrift_framed_transport_size_in_mb => $thrift_framed_transport_size_in_mb,
    enable_transient_replication     => $enable_transient_replication,
  }
}
        `.trim(),
    },
  },
  role_cassandra_pfpt: {
    'metadata.json': `
{
  "name": "role_cassandra_pfpt",
  "version": "1.0.0",
  "author": "Puppet",
  "summary": "Puppet role for a Cassandra server.",
  "license": "Apache-2.0",
  "source": "",
  "project_page": "",
  "issues_url": "",
  "dependencies": [
    { "name": "profile_cassandra_pfpt", "version_requirement": ">= 1.0.0" }
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
