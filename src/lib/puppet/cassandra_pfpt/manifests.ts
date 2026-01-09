
export const manifests = {
      'init.pp': `
# @summary Main component class for managing Cassandra.
# This class is fully parameterized and should receive its data from a profile.
class cassandra_pfpt (
  String $cassandra_version,
  String $java_version,
  Optional[String] $java_package_name,
  Boolean $manage_repo,
  String $user,
  String $group,
  String $repo_baseurl,
  String $repo_gpgkey,
  Boolean $repo_gpgcheck,
  Integer $repo_priority,
  Boolean $repo_skip_if_unavailable,
  Boolean $repo_sslverify,
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
  String $https_domain,
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
  Boolean $enable_transient_replication,
  Boolean $manage_jmx_security,
  String $jmx_password_file_content,
  String $jmx_access_file_content,
  String $jmx_password_file_path,
  String $jmx_access_file_path,
  String $service_timeout_start_sec,
  Optional[String] $authorizer,
  Optional[String] $authenticator,
  Optional[Integer] $num_tokens,
  Optional[Integer] $native_transport_port,
  Optional[String] $endpoint_snitch,
  Optional[String] $listen_interface,
  Optional[String] $rpc_interface,
  Optional[String] $broadcast_address,
  Optional[String] $broadcast_rpc_address,
  Optional[Integer] $counter_cache_size_in_mb,
  Optional[Integer] $key_cache_size_in_mb,
  Optional[String] $disk_optimization_strategy,
  Optional[Boolean] $auto_snapshot,
  Optional[Integer] $phi_convict_threshold,
  Optional[Integer] $concurrent_reads,
  Optional[Integer] $concurrent_writes,
  Optional[Integer] $concurrent_counter_writes,
  Optional[String] $memtable_allocation_type,
  Optional[Integer] $index_summary_capacity_in_mb,
  Optional[Integer] $file_cache_size_in_mb
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

  if $java_package_name and $java_package_name != '' {
    $actual_java_package = $java_package_name
  } else {
    $actual_java_package = $java_version ? {
      '8'     => 'java-1.8.0-openjdk-headless',
      '11'    => 'java-11-openjdk-headless',
      '17'    => 'java-17-openjdk-headless',
      default => "java-\\\${java_version}-openjdk-headless",
    }
  }

  package { $actual_java_package:
    ensure  => 'present',
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
      $os_release_major = regsubst($facts['os']['release']['full'], '^(\\\\d+).*$', '\\\\1')
      yumrepo { 'cassandra':
        descr               => "Apache Cassandra \\\${cassandra_version} for EL\\\${os_release_major}",
        baseurl             => $repo_baseurl,
        enabled             => 1,
        gpgcheck            => $repo_gpgcheck,
        gpgkey              => $repo_gpgkey,
        priority            => $repo_priority,
        skip_if_unavailable => $repo_skip_if_unavailable,
        sslverify           => $repo_sslverify,
        require             => Group[$group],
      }
    }
    # Add logic for other OS families like Debian if needed
  }

  package { $package_dependencies:
    ensure  => 'present',
    require => Class['cassandra_pfpt::java'],
  }

  $cassandra_ensure = $cassandra_version ? {
    undef   => 'present',
    default => $cassandra_version,
  }

  package { 'cassandra':
    ensure  => $cassandra_ensure,
    require => [ Class['cassandra_pfpt::java'], User[$user], Yumrepo['cassandra'] ],
    before  => Class['cassandra_pfpt::config'],
  }

  package { 'cassandra-tools':
    ensure  => $cassandra_ensure,
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
    require => Package['cassandra'],
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
    require => Package['cassandra'],
  }

  file { '/etc/cassandra/conf/cassandra.yaml':
    ensure  => 'file',
    content => template('cassandra_pfpt/cassandra.yaml.erb'),
    owner   => $user,
    group   => $group,
    mode    => '0644',
    require => Package['cassandra'],
    notify  => Class['cassandra_pfpt::service'],
  }

  file { '/etc/cassandra/conf/cassandra-rackdc.properties':
    ensure  => 'file',
    content => template('cassandra_pfpt/cassandra-rackdc.properties.erb'),
    owner   => $user,
    group   => $group,
    mode    => '0644',
    require => Package['cassandra'],
    notify  => Class['cassandra_pfpt::service'],
  }

  file { '/etc/cassandra/conf/jvm-server.options':
    ensure  => 'file',
    content => template('cassandra_pfpt/jvm-server.options.erb'),
    owner   => $user,
    group   => $group,
    mode    => '0644',
    require => Package['cassandra'],
    notify  => Class['cassandra_pfpt::service'],
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
    file { "\\\${manage_bin_dir}/\\\${script}":
      ensure  => 'file',
      source  => "puppet:///modules/cassandra_pfpt/scripts/\\\${script}",
      owner   => 'root',
      group   => 'root',
      mode    => '0755',
      require => File[$manage_bin_dir],
    }
  }

  if $disable_swap {
    exec { 'swapoff -a':
      command => '/sbin/swapoff -a',
      unless  => '/sbin/swapon -s | /bin/grep -qE "^/[^ ]+\\\\s+partition\\\\s+0\\\\s+0\\$"',
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

  if !empty($merged_sysctl) {
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
  }

  if !empty($limits_settings) {
    file { '/etc/security/limits.d/cassandra.conf':
      ensure  => 'file',
      content => template('cassandra_pfpt/cassandra_limits.conf.erb'),
    }
  }

  if $ssl_enabled {
    exec { 'create the certs dir':
      command => "mkdir -p \\\${target_dir}/etc",
      path    => '/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin',
      unless  => "test -d \\\${target_dir}/etc",
    }

    notify { 'ssl_certificate_placeholder':
      message => "Placeholder for ssl_certificate custom type. This would generate certs for domain \\\${https_domain} in \\\${target_dir}/etc.",
      require => Exec['create the certs dir'],
    }

    notify { 'java_ks_placeholder':
      message => "Placeholder for java_ks custom type. This would create \\\${keystore_path} from the generated certs.",
      require => Notify['ssl_certificate_placeholder'],
    }

    file { $keystore_path:
      ensure  => 'file',
      owner   => 'root',
      group   => 'root',
      mode    => '0444',
      require => Notify['java_ks_placeholder'],
    }

    file { $truststore_path:
      ensure  => link,
      target  => $keystore_path,
      require => File[$keystore_path],
    }
  }

  if $manage_jmx_security {
    file { $jmx_password_file_path:
      ensure  => 'file',
      content => $jmx_password_file_content,
      owner   => $user,
      group   => $group,
      mode    => '0400',
      require => Package['cassandra'],
      notify  => Class['cassandra_pfpt::service'],
    }

    file { $jmx_access_file_path:
      ensure  => 'file',
      content => $jmx_access_file_content,
      owner   => $user,
      group   => $group,
      mode    => '0400',
      require => Package['cassandra'],
      notify  => Class['cassandra_pfpt::service'],
    }
  }

  if $facts['os']['family'] == 'RedHat' and $facts['os']['release']['major'] >= '7' {
    file { '/etc/systemd/system/cassandra.service.d':
      ensure => 'directory',
      owner  => 'root',
      group  => 'root',
      mode   => '0755',
    }

    file { '/etc/systemd/system/cassandra.service.d/override.conf':
      ensure  => 'file',
      content => template('cassandra_pfpt/cassandra.service.d.erb'),
      owner   => 'root',
      group   => 'root',
      mode    => '0644',
      notify  => Exec['cassandra-systemd-reload'],
      require => File['/etc/systemd/system/cassandra.service.d'],
    }

    exec { 'cassandra-systemd-reload':
      command     => 'systemctl daemon-reload',
      path        => ['/bin', '/usr/bin'],
      refreshonly => true,
      before      => Class['cassandra_pfpt::service'],
    }
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
    require    => [
      Package['cassandra'],
      File['/etc/cassandra/conf/cassandra.yaml'],
      File['/etc/cassandra/conf/cassandra-rackdc.properties'],
      File['/etc/cassandra/conf/jvm-server.options'],
    ],
  }

  file { $change_password_cql:
    ensure  => file,
    content => "ALTER USER cassandra WITH PASSWORD '\\\${cassandra_password}';\\\\n",
    owner   => 'root',
    group   => 'root',
    mode    => '0600',
  }

  exec { 'change_cassandra_password':
    command   => "cqlsh -u cassandra -p cassandra -f \\\${change_password_cql}",
    path      => ['/bin/', $cqlsh_path_env],
    tries     => 12,
    try_sleep => 10,
    unless    => "cqlsh -u cassandra -p '\\\${cassandra_password}' -e 'SELECT cluster_name FROM system.local;' \\\${listen_address} >/dev/null 2>&1",
    require   => [Service['cassandra'], File[$change_password_cql]],
  }

  if $enable_range_repair {
    $range_repair_ensure = $enable_range_repair ? { true => 'running', default => 'stopped' }
    $range_repair_enable = $enable_range_repair ? { true => true, default => false }

    file { '/etc/systemd/system/range-repair.service':
      ensure  => 'file',
      content => template('cassandra_pfpt/range-repair.service.erb'),
      owner   => 'root',
      group   => 'root',
      mode    => '0644',
      notify  => Exec['systemctl_daemon_reload_range_repair'],
      require => File["\\\${manage_bin_dir}/range-repair.sh"],
    }

    exec { 'systemctl_daemon_reload_range_repair':
      command     => '/bin/systemctl daemon-reload',
      path        => ['/usr/bin', '/bin'],
      refreshonly => true,
    }

    service { 'range-repair':
      ensure    => $range_repair_ensure,
      enable    => $range_repair_enable,
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
  # Example:
  # firewall { '100 allow cassandra gossip':
  #   dport  => 7000,
  #   proto  => 'tcp',
  #   action => 'accept',
  # }
  # firewall { '101 allow cassandra thrift':
  #   dport  => 9160,
  #   proto  => 'tcp',
  #   action => 'accept',
  # }
}
`.trim(),
    };

    