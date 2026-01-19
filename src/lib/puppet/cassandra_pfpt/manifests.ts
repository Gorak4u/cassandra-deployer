
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
  Array[String] $seeds_list = [],
  String $listen_address,
  String $datacenter,
  String $rack,
  String $data_dir,
  String $saved_caches_dir,
  String $commitlog_dir,
  String $hints_directory,
  String $max_heap_size,
  String $gc_type,
  Hash $extra_jvm_args_override = {},
  String $cassandra_password,
  String $replace_address,
  Boolean $disable_swap,
  Hash $sysctl_settings,
  Hash $limits_settings,
  String $manage_bin_dir,
  String $jamm_source,
  String $jamm_target,
  Boolean $enable_range_repair,
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
  Optional[String] $initial_token,
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
  Optional[Integer] $file_cache_size_in_mb,
  Boolean $manage_coralogix_agent,
  String $coralogix_api_key,
  String $coralogix_region,
  Boolean $coralogix_logs_enabled,
  Boolean $coralogix_metrics_enabled,
  Boolean $enable_materialized_views,
  Optional[String] $coralogix_baseurl = undef,
  Hash $system_keyspaces_replication = {},
  Hash $cassandra_roles = {},
  Boolean $manage_jmx_exporter,
  String $jmx_exporter_version,
  String $jmx_exporter_jar_source,
  String $jmx_exporter_jar_target,
  String $jmx_exporter_config_source,
  String $jmx_exporter_config_target,
  Integer $jmx_exporter_port,
  Boolean $manage_full_backups = false,
  Boolean $manage_incremental_backups = false,
  String $full_backup_schedule = 'daily',
  Variant[String, Array[String]] $incremental_backup_schedule = '0 */4 * * *',
  String $backup_s3_bucket = 'your-s3-backup-bucket',
  String $full_backup_script_path = '/usr/local/bin/full-backup-to-s3.sh',
  String $incremental_backup_script_path = '/usr/local/bin/incremental-backup-to-s3.sh',
  String $full_backup_log_file = '/var/log/cassandra/full_backup.log',
  String $incremental_backup_log_file = '/var/log/cassandra/incremental_backup.log',
  Optional[String] $puppet_cron_schedule = undef,
) {
  # Validate Java and Cassandra version compatibility
  $cassandra_major_version = split($cassandra_version, '[.-]')[0]
  if Integer($cassandra_major_version) >= 4 and Integer($java_version) < 11 {
    fail("Cassandra version \${cassandra_version} requires Java 11 or newer, but Java \${java_version} was specified.")
  }
  if Integer($cassandra_major_version) <= 3 and Integer($java_version) > 11 {
    fail("Cassandra version \${cassandra_version} is not compatible with Java versions newer than 11, but Java \${java_version} was specified.")
  }
  # If seed list is empty, default to self-seeding. This is crucial for bootstrapping.
  $seeds = if empty($seeds_list) {
    [$facts['networking']['ip']]
  } else {
    $seeds_list
  }
  
  # Calculate default JVM args based on GC type and Java version
  $default_jvm_args_hash = if $gc_type == 'G1GC' and versioncmp($java_version, '14') < 0 {
    {
      'G1HeapRegionSize'             => '-XX:G1HeapRegionSize=16M',
      'MaxGCPauseMillis'             => '-XX:MaxGCPauseMillis=500',
      'InitiatingHeapOccupancyPercent' => '-XX:InitiatingHeapOccupancyPercent=75',
      'ParallelRefProcEnabled'       => '-XX:+ParallelRefProcEnabled',
      'AggressiveOpts'               => '-XX:+AggressiveOpts',
    }
  } elsif $gc_type == 'CMS' and versioncmp($java_version, '14') < 0 {
    {
      'UseConcMarkSweepGC'          => '-XX:+UseConcMarkSweepGC',
      'CMSParallelRemarkEnabled'    => '-XX:+CMSParallelRemarkEnabled',
      'SurvivorRatio'               => '-XX:SurvivorRatio=8',
      'MaxTenuringThreshold'        => '-XX:MaxTenuringThreshold=1',
      'CMSInitiatingOccupancyFraction' => '-XX:CMSInitiatingOccupancyFraction=75',
      'UseCMSInitiatingOccupancyOnly' => '-XX:+UseCMSInitiatingOccupancyOnly',
      'CMSClassUnloadingEnabled'    => '-XX:+CMSClassUnloadingEnabled',
      'AlwaysPreTouch'              => '-XX:+AlwaysPreTouch',
    }
  } else {
    {}
  }
  
  # Merge the default arguments with any overrides from Hiera. Hiera wins.
  $merged_jvm_args_hash = $default_jvm_args_hash + $extra_jvm_args_override
  $extra_jvm_args = $merged_jvm_args_hash.values
  contain cassandra_pfpt::java
  contain cassandra_pfpt::install
  contain cassandra_pfpt::config
  contain cassandra_pfpt::service
  contain cassandra_pfpt::firewall
  contain cassandra_pfpt::system_keyspaces
  contain cassandra_pfpt::roles
  if $manage_jmx_exporter {
    contain cassandra_pfpt::jmx_exporter
  }
  if $manage_coralogix_agent {
    contain cassandra_pfpt::coralogix
    Class['cassandra_pfpt::config'] -> Class['cassandra_pfpt::coralogix']
  }
  if $manage_full_backups or $manage_incremental_backups {
    contain cassandra_pfpt::backup
  }
  
  # Manage the puppet agent itself
  contain cassandra_pfpt::puppet

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
      default => "java-\${java_version}-openjdk-headless",
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
      $os_release_major = regsubst($facts['os']['release']['full'], '^(\\d+).*$', '\\1')
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
    require => [ Class['cassandra_pfpt::java'], User[$user], Group[$group], Yumrepo['cassandra'] ],
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
  file { [$data_dir, $commitlog_dir, $saved_caches_dir, $hints_directory, $cdc_raw_directory]:
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
    'full-backup-to-s3.sh', 'incremental-backup-to-s3.sh', 'prepare-replacement.sh', 'version-check.sh',
    'cassandra_range_repair.py', 'range-repair.sh', 'robust_backup.sh',
    'restore-from-s3.sh', 'node_health_check.sh', 'rolling_restart.sh',
    'disk-health-check.sh', 'decommission-node.sh', 'compaction-manager.sh' ].each |$script| {
    file { "\\\${manage_bin_dir}/\\\${script}":
      ensure  => 'file',
      source  => "puppet:///modules/cassandra_pfpt/\\\${script}",
      owner   => 'root',
      group   => 'root',
      mode    => '0755',
      require => File[$manage_bin_dir],
    }
  }
  if $disable_swap {
    exec { 'swapoff -a':
      command => '/sbin/swapoff -a',
      unless  => '/sbin/swapon -s | /bin/grep -qE "^/[^ ]+\\\\s+partition\\\\s+0\\\\s*$"',
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
      command => "mkdir -p \${target_dir}/etc",
      path    => '/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin',
      unless  => "test -d \${target_dir}/etc",
    }
    # Custom type that generates cert/key files for the domain
    ssl_certificate { "\${target_dir}/etc/keystore":
      domain  => $https_domain,
      require => Exec['create the certs dir'],
    }
    # Java keystore creation: JKS from PEM + KEY
    java_ks { "host:\${target_dir}/etc/keystore.jks":
      ensure      => latest,
      certificate => "\${target_dir}/etc/keystore.pem",
      private_key => "\${target_dir}/etc/keystore.key",
      password    => $keystore_password,
      require     => [
        File["\${target_dir}/etc/keystore.jks"],
        Ssl_certificate["\${target_dir}/etc/keystore"], # ensure certs exist first
      ],
    }
    file { "\${target_dir}/etc/keystore.jks":
      ensure  => file,
      owner   => 'root',
      group   => 'root',
      mode    => '0444',
      require => Ssl_certificate["\${target_dir}/etc/keystore"],
    }
    file { "\${target_dir}/etc/truststore.jks":
      ensure  => link,
      target  => "\${target_dir}/etc/keystore.jks",
      require => File["\${target_dir}/etc/keystore.jks"],
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
  if $facts['os']['family'] == 'RedHat' and Integer($facts['os']['release']['major']) >= 7 {
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
    ensure  => 'file',
    content => "ALTER USER cassandra WITH PASSWORD '\${cassandra_password}';",
    owner   => 'root',
    group   => 'root',
    mode    => '0600',
  }
  $cqlsh_ssl_opt = $ssl_enabled ? {
    true  => '--ssl',
    false => '',
  }
  # Change only if new password isn't already active
  exec { 'change_cassandra_password':
    command     => "cqlsh \${cqlsh_ssl_opt} -u cassandra -p cassandra -f \${change_password_cql} \${listen_address}",
    path        => ['/bin', '/usr/bin', $cqlsh_path_env],
    timeout     => 60,
    tries       => 2,
    try_sleep   => 10,
    logoutput   => on_failure,
    # If we can connect with the *new* password, skip running the ALTER
    unless      => "cqlsh \${cqlsh_ssl_opt} -u cassandra -p '\${cassandra_password}' -e \\"SELECT cluster_name FROM system.local;\\" \${listen_address} >/dev/null 2>&1",
    require     => [ Service['cassandra'], File[$change_password_cql] ],
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
      require => File["\${manage_bin_dir}/range-repair.sh"],
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
    'coralogix.pp': `
# @summary Manages Coralogix agent installation and configuration.
class cassandra_pfpt::coralogix inherits cassandra_pfpt {
  if $facts['os']['family'] == 'RedHat' {
    $repo_url = $coralogix_baseurl ? {
      undef   => 'https://yum.coralogix.com/coralogix-el8-x86_64',
      default => $coralogix_baseurl,
    }
    yumrepo { 'coralogix':
      ensure   => 'present',
      baseurl  => $repo_url,
      descr    => 'coralogix repo',
      enabled  => 1,
      gpgcheck => 0,
    }
    package { 'coralogix-agent':
      ensure  => 'installed',
      require => Yumrepo['coralogix'],
    }
    file { '/etc/coralogix/agent.conf':
      ensure  => 'file',
      content => template('cassandra_pfpt/coralogix-agent.conf.erb'),
      owner   => 'root',
      group   => 'root',
      mode    => '0640',
      require => Package['coralogix-agent'],
      notify  => Service['coralogix-agent'],
    }
    service { 'coralogix-agent':
      ensure    => 'running',
      enable    => true,
      hasstatus => true,
      require   => File['/etc/coralogix/agent.conf'],
    }
  }
}
    `.trim(),
    'system_keyspaces.pp': `
# @summary Manages system keyspace replication for multi-DC clusters.
class cassandra_pfpt::system_keyspaces inherits cassandra_pfpt {
  # Only proceed if a replication strategy is defined.
  if !empty($system_keyspaces_replication) {
    # The system_keyspaces_replication is a hash like {'dc1' => 3, 'dc2' => 3}
    # We need to convert it to a string like "'dc1': '3', 'dc2': '3'"
    $replication_map_parts = $system_keyspaces_replication.map |$dc, $rf| {
      "' \${dc}': '\${rf}'"
    }
    $replication_map_string = join($replication_map_parts, ', ')
    $replication_cql_string = "{'class': 'NetworkTopologyStrategy', \${replication_map_string}}"
    # Define the command to alter keyspaces
    $alter_auth_cql = "ALTER KEYSPACE system_auth WITH replication = \${replication_cql_string}"
    $alter_dist_cql = "ALTER KEYSPACE system_distributed WITH replication = \${replication_cql_string}"
    $alter_traces_cql = "ALTER KEYSPACE system_traces WITH replication = \${replication_cql_string}"
    # Use a single check for idempotency. This isn't perfect but is simpler.
    # It checks if the string for system_auth's replication is what we expect.
    $check_command = "cqlsh \${cqlsh_ssl_opt} -u cassandra -p '\${cassandra_password}' \${listen_address} -e \\"DESCRIBE KEYSPACE system_auth;\\" | grep -q \\"replication = \${replication_cql_string}\\""
    exec { 'update_system_keyspace_replication':
      command   => "cqlsh \${cqlsh_ssl_opt} -u cassandra -p '\${cassandra_password}' \${listen_address} -e \\"\${alter_auth_cql}; \${alter_dist_cql}; \${alter_traces_cql};\\"",
      path      => ['/bin', '/usr/bin', $cqlsh_path_env],
      unless    => $check_command,
      logoutput => on_failure,
      require   => Exec['change_cassandra_password'], # Ensure password is set first
    }
  }
}
        `.trim(),
    'roles.pp': `
# @summary Manages Cassandra user roles based on Hiera data.
class cassandra_pfpt::roles inherits cassandra_pfpt {
  if !empty($cassandra_roles) {
    $cassandra_roles.each |$role_name, $role_details| {
      # For each role defined in Hiera, create a temporary CQL file
      $cql_file_path = "/tmp/create_role_\${role_name}.cql"
      $role_options = "WITH SUPERUSER = \${role_details['is_superuser']} AND LOGIN = \${role_details['can_login']} AND PASSWORD = '\${role_details['password']}'"
      $create_cql = "CREATE ROLE IF NOT EXISTS \\"\${role_name}\\" \${role_options};"
      file { $cql_file_path:
        ensure  => 'file',
        content => $create_cql,
        owner   => 'root',
        group   => 'root',
        mode    => '0600',
      }
      # Execute the CQL file to create or update the role
      exec { "create_cassandra_role_\${role_name}":
        command => "cqlsh \${cqlsh_ssl_opt} -u cassandra -p '\${cassandra_password}' -f \${cql_file_path} \${listen_address}",
        path    => ['/bin', '/usr/bin', $cqlsh_path_env],
        # Only run if the role doesn't exist. This isn't perfect for password updates but prevents rerunning CREATE ROLE.
        # A more robust check might query system_auth.roles.
        unless  => "cqlsh \${cqlsh_ssl_opt} -u cassandra -p '\${cassandra_password}' -e \\"DESCRIBE ROLE \\\\"\\"\\"\${role_name}\\\\"\\";\\" \${listen_address}",
        require => [Exec['change_cassandra_password'], File[$cql_file_path]],
      }
    }
  }
}
`.trim(),
    'jmx_exporter.pp': `
# @summary Manages the Prometheus JMX Exporter for Cassandra.
class cassandra_pfpt::jmx_exporter inherits cassandra_pfpt {
  # Ensure the JMX exporter JAR is present on the node
  file { $jmx_exporter_jar_target:
    ensure => 'file',
    owner  => 'root',
    group  => 'root',
    mode   => '0644',
    source => $jmx_exporter_jar_source,
  }
  # Manage the JMX exporter configuration file
  file { $jmx_exporter_config_target:
    ensure  => 'file',
    owner   => $user,
    group   => $group,
    mode    => '0644',
    source  => $jmx_exporter_config_source,
    require => Package['cassandra'],
  }
}
`.trim(),
    'backup.pp': `
# @summary Manages scheduled backups for Cassandra using a DIY script.
class cassandra_pfpt::backup inherits cassandra_pfpt {
  # This class is responsible for scheduling the execution of the backup scripts.
  # The backup scripts themselves are managed by the main config class.

  if $manage_full_backups or $manage_incremental_backups {
    # Ensure the backup config directory exists
    file { '/etc/backup':
      ensure => 'directory',
      owner  => 'root',
      group  => 'root',
      mode   => '0755',
    }
    
    # Manage the backup configuration file
    file { '/etc/backup/config.json':
      ensure  => 'file',
      owner   => 'root',
      group   => 'root',
      mode    => '0644',
      content => template('cassandra_pfpt/backup.config.json.erb'),
      require => File['/etc/backup'],
    }
  }

  if $manage_full_backups {
    # Full Backup Service and Timer
    file { '/etc/systemd/system/cassandra-full-backup.service':
      ensure  => 'file',
      owner   => 'root',
      group   => 'root',
      mode    => '0644',
      content => template('cassandra_pfpt/cassandra-full-backup.service.erb'),
      notify  => Exec['cassandra-backup-systemd-reload'],
    }
    file { '/etc/systemd/system/cassandra-full-backup.timer':
      ensure  => 'file',
      owner   => 'root',
      group   => 'root',
      mode    => '0644',
      content => template('cassandra_pfpt/cassandra-full-backup.timer.erb'),
      notify  => Service['cassandra-full-backup.timer'],
    }
    service { 'cassandra-full-backup.timer':
      ensure  => 'running',
      enable  => true,
      require => [
        File['/etc/systemd/system/cassandra-full-backup.service'],
        File['/etc/systemd/system/cassandra-full-backup.timer'],
        File['/etc/backup/config.json'],
      ],
    }
  }

  if $manage_incremental_backups {
    # Incremental Backup Service and Timer
    file { '/etc/systemd/system/cassandra-incremental-backup.service':
      ensure  => 'file',
      owner   => 'root',
      group   => 'root',
      mode    => '0644',
      content => template('cassandra_pfpt/cassandra-incremental-backup.service.erb'),
      notify  => Exec['cassandra-backup-systemd-reload'],
    }
    file { '/etc/systemd/system/cassandra-incremental-backup.timer':
      ensure  => 'file',
      owner   => 'root',
      group   => 'root',
      mode    => '0644',
      content => template('cassandra_pfpt/cassandra-incremental-backup.timer.erb'),
      notify  => Service['cassandra-incremental-backup.timer'],
    }
    service { 'cassandra-incremental-backup.timer':
      ensure  => 'running',
      enable  => true,
      require => [
        File['/etc/systemd/system/cassandra-incremental-backup.service'],
        File['/etc/systemd/system/cassandra-incremental-backup.timer'],
        File['/etc/backup/config.json'],
      ],
    }
  }

  # Common daemon-reload exec, triggered by any service file change.
  # This only runs if at least one of the backup types is enabled.
  exec { 'cassandra-backup-systemd-reload':
    command     => 'systemctl daemon-reload',
    path        => ['/bin', '/usr/bin'],
    refreshonly => true,
  }
}
`.trim(),
    'puppet.pp': `
# @summary Manages the Puppet agent itself, including scheduled runs.
class cassandra_pfpt::puppet inherits cassandra_pfpt {
  # Stagger the cron job across the hour to avoid all nodes running at once.
  $cron_minute_1 = fqdn_rand(30)
  $cron_minute_2 = $cron_minute_1 + 30
  
  # Default schedule: runs twice an hour, staggered.
  $default_schedule = "\${cron_minute_1},\${cron_minute_2} * * * *"
  
  # Use the schedule from the parameter if provided, otherwise use the staggered default.
  $final_schedule = pick($puppet_cron_schedule, $default_schedule)

  cron { 'scheduled_puppet_run':
    command  => '[ ! -f /var/lib/puppet-disabled ] && /opt/puppetlabs/bin/puppet agent -v --onetime',
    user     => 'root',
    minute   => split($final_schedule, ' ')[0],
    hour     => split($final_schedule, ' ')[1],
    monthday => split($final_schedule, ' ')[2],
    month    => split($final_schedule, ' ')[3],
    weekday  => split($final_schedule, ' ')[4],
  }
}
`.trim()
    };


    
