

export const manifests = {
      'init.pp': `
# @summary Profile for configuring a Cassandra node.
# This class wraps the cassandra_pfpt component module and provides
# configuration data via Hiera.
class profile_cassandra_pfpt {
  $cassandra_version                = lookup('profile_cassandra_pfpt::cassandra_version', { 'default_value' => '4.1.10-1' })
  $java_version                     = lookup('profile_cassandra_pfpt::java_version', { 'default_value' => '11' })
  $java_package_name                = lookup('profile_cassandra_pfpt::java_package_name', { 'default_value' => undef })
  $use_java11                       = lookup('profile_cassandra_pfpt::use_java11', { 'default_value' => true })
  $cluster_name                     = lookup('profile_cassandra_pfpt::cluster_name', { 'default_value' => 'pfpt-cassandra-cluster' })
  $seeds                            = lookup('profile_cassandra_pfpt::seeds', { 'default_value' => [$facts['networking']['ip']] })
  $use_shenandoah_gc                = lookup('profile_cassandra_pfpt::use_shenandoah_gc', { 'default_value' => false })
  $racks                            = lookup('profile_cassandra_pfpt::racks', { 'default_value' => {} })
  $datacenter                       = lookup('profile_cassandra_pfpt::datacenter', { 'default_value' => 'dc1' })
  $rack                             = lookup('profile_cassandra_pfpt::rack', { 'default_value' => 'rack1' })
  $cassandra_password               = lookup('profile_cassandra_pfpt::cassandra_password', { 'default_value' => 'PP#C@ss@ndr@000' })
  $max_heap_size                    = lookup('profile_cassandra_pfpt::max_heap_size', { 'default_value' => '3G' })
  $gc_type                          = lookup('profile_cassandra_pfpt::gc_type', { 'default_value' => 'G1GC' })
  $data_dir                         = lookup('profile_cassandra_pfpt::data_dir', { 'default_value' => '/var/lib/cassandra/data' })
  $commitlog_dir                    = lookup('profile_cassandra_pfpt::commitlog_dir', { 'default_value' => '/var/lib/cassandra/commitlog' })
  $saved_caches_dir                 = lookup('profile_cassandra_pfpt::saved_caches_dir', { 'default_value' => '/var/lib/cassandra/saved_caches' })
  $hints_directory                  = lookup('profile_cassandra_pfpt::hints_directory', { 'default_value' => '/var/lib/cassandra/hints' })
  $disable_swap                     = lookup('profile_cassandra_pfpt::disable_swap', { 'default_value' => false })
  $replace_address                  = lookup('profile_cassandra_pfpt::replace_address', { 'default_value' => '' })
  $enable_range_repair              = lookup('profile_cassandra_pfpt::enable_range_repair', { 'default_value' => false })
  $listen_address                   = lookup('profile_cassandra_pfpt::listen_address', { 'default_value' => $facts['networking']['ip'] })
  $ssl_enabled                      = lookup('profile_cassandra_pfpt::ssl_enabled', { 'default_value' => false })
  $https_domain                     = lookup('profile_cassandra_pfpt::https_domain', { 'default_value' => $facts['networking']['fqdn'] })
  $target_dir                       = lookup('profile_cassandra_pfpt::target_dir', { 'default_value' => '/etc/pki/tls/certs' })
  $keystore_path                    = lookup('profile_cassandra_pfpt::keystore_path', { 'default_value' => '/etc/pki/tls/certs/etc/keystore.jks' })
  $keystore_password                = lookup('profile_cassandra_pfpt::keystore_password', { 'default_value' => 'ChangeMe' })
  $truststore_path                  = lookup('profile_cassandra_pfpt::truststore_path', { 'default_value' => '/etc/pki/ca-trust/extracted/java/cacerts' })
  $truststore_password              = lookup('profile_cassandra_pfpt::truststore_password', { 'default_value' => 'changeit' })
  $internode_encryption             = lookup('profile_cassandra_pfpt::internode_encryption', { 'default_value' => 'all' })
  $internode_require_client_auth    = lookup('profile_cassandra_pfpt::internode_require_client_auth', { 'default_value' => true })
  $client_optional                  = lookup('profile_cassandra_pfpt::client_optional', { 'default_value' => false })
  $client_require_client_auth       = lookup('profile_cassandra_pfpt::client_require_client_auth', { 'default_value' => false })
  $client_keystore_path             = lookup('profile_cassandra_pfpt::client_keystore_path', { 'default_value' => '/etc/pki/tls/certs/etc/keystore.jks' })
  $client_truststore_path           = lookup('profile_cassandra_pfpt::client_truststore_path', { 'default_value' => '/etc/pki/ca-trust/extracted/java/cacerts' })
  $client_truststore_password       = lookup('profile_cassandra_pfpt::client_truststore_password', { 'default_value' => 'changeit' })
  $tls_protocol                     = lookup('profile_cassandra_pfpt::tls_protocol', { 'default_value' => 'TLS' })
  $tls_algorithm                    = lookup('profile_cassandra_pfpt::tls_algorithm', { 'default_value' => 'SunX509' })
  $store_type                       = lookup('profile_cassandra_pfpt::store_type', { 'default_value' => 'JKS' })
  $concurrent_compactors            = lookup('profile_cassandra_pfpt::concurrent_compactors', { 'default_value' => 4 })
  $compaction_throughput_mb_per_sec = lookup('profile_cassandra_pfpt::compaction_throughput_mb_per_sec', { 'default_value' => 16 })
  $tombstone_warn_threshold         = lookup('profile_cassandra_pfpt::tombstone_warn_threshold', { 'default_value' => 1000 })
  $tombstone_failure_threshold      = lookup('profile_cassandra_pfpt::tombstone_failure_threshold', { 'default_value' => 100000 })
  $sysctl_settings                  = lookup('profile_cassandra_pfpt::sysctl_settings', { 'default_value' => { 'fs.aio-max-nr' => 1048576 } })
  $limits_settings                  = lookup('profile_cassandra_pfpt::limits_settings', { 'default_value' => { 'memlock' => 'unlimited', 'nofile' => 100000, 'nproc' => 32768, 'as' => 'unlimited' } })
  $manage_repo                      = lookup('profile_cassandra_pfpt::manage_repo', { 'default_value' => true })
  $user                             = lookup('profile_cassandra_pfpt::user', { 'default_value' => 'cassandra' })
  $group                            = lookup('profile_cassandra_pfpt::group', { 'default_value' => 'cassandra' })
  $repo_baseurl                     = lookup('profile_cassandra_pfpt::repo_baseurl', { 'default_value' => 'https://repocache.nonprod.ppops.net/artifactory/apache-org-cassandra/' })
  $repo_gpgkey                      = lookup('profile_cassandra_pfpt::repo_gpgkey', { 'default_value' => 'https://repocache.nonprod.ppops.net/artifactory/apache-org-cassandra-gpg-keys/KEYS' })
  $repo_gpgcheck                    = lookup('profile_cassandra_pfpt::repo_gpgcheck', { 'default_value' => true })
  $repo_priority                    = lookup('profile_cassandra_pfpt::repo_priority', { 'default_value' => 99 })
  $repo_skip_if_unavailable         = lookup('profile_cassandra_pfpt::repo_skip_if_unavailable', { 'default_value' => true })
  $repo_sslverify                   = lookup('profile_cassandra_pfpt::repo_sslverify', { 'default_value' => true })
  $package_dependencies             = lookup('profile_cassandra_pfpt::package_dependencies', { 'default_value' => ['cyrus-sasl-plain', 'jemalloc', 'python3', 'numactl'] })
  $manage_bin_dir                   = lookup('profile_cassandra_pfpt::manage_bin_dir', { 'default_value' => '/usr/local/bin' })
  $change_password_cql              = lookup('profile_cassandra_pfpt::change_password_cql', { 'default_value' => '/tmp/change_password.cql' })
  $cqlsh_path_env                   = lookup('profile_cassandra_pfpt::cqlsh_path_env', { 'default_value' => '/usr/bin/' })
  $jamm_target                      = lookup('profile_cassandra_pfpt::jamm_target', { 'default_value' => '/usr/share/cassandra/lib/jamm-0.3.2.jar' })
  $jamm_source                      = lookup('profile_cassandra_pfpt::jamm_source', { 'default_value' => 'puppet:///modules/cassandra_pfpt/jamm-0.3.2.jar' })
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
  $manage_jmx_security              = lookup('profile_cassandra_pfpt::manage_jmx_security', { 'default_value' => true })
  $jmx_password_file_content        = lookup('profile_cassandra_pfpt::jmx_password_file_content', { 'default_value' => "monitorRole QED\\ncontrolRole R&D" })
  $jmx_access_file_content          = lookup('profile_cassandra_pfpt::jmx_access_file_content', { 'default_value' => "monitorRole readonly\\ncontrolRole readwrite" })
  $jmx_password_file_path           = lookup('profile_cassandra_pfpt::jmx_password_file_path', { 'default_value' => '/etc/cassandra/jmxremote.password' })
  $jmx_access_file_path             = lookup('profile_cassandra_pfpt::jmx_access_file_path', { 'default_value' => '/etc/cassandra/jmxremote.access' })
  $service_timeout_start_sec        = lookup('profile_cassandra_pfpt::service_timeout_start_sec', { 'default_value' => '400s' })
  $authorizer                       = lookup('profile_cassandra_pfpt::authorizer', { 'default_value' => 'CassandraAuthorizer' })
  $authenticator                    = lookup('profile_cassandra_pfpt::authenticator', { 'default_value' => 'PasswordAuthenticator' })
  $num_tokens                       = lookup('profile_cassandra_pfpt::num_tokens', { 'default_value' => 256 })
  $native_transport_port            = lookup('profile_cassandra_pfpt::native_transport_port', { 'default_value' => 9042 })
  $endpoint_snitch                  = lookup('profile_cassandra_pfpt::endpoint_snitch', { 'default_value' => 'GossipingPropertyFileSnitch' })
  $listen_interface                 = lookup('profile_cassandra_pfpt::listen_interface', { 'default_value' => undef })
  $rpc_interface                    = lookup('profile_cassandra_pfpt::rpc_interface', { 'default_value' => undef })
  $broadcast_address                = lookup('profile_cassandra_pfpt::broadcast_address', { 'default_value' => undef })
  $broadcast_rpc_address            = lookup('profile_cassandra_pfpt::broadcast_rpc_address', { 'default_value' => undef })
  $counter_cache_size_in_mb         = lookup('profile_cassandra_pfpt::counter_cache_size_in_mb', { 'default_value' => undef })
  $key_cache_size_in_mb             = lookup('profile_cassandra_pfpt::key_cache_size_in_mb', { 'default_value' => undef })
  $disk_optimization_strategy       = lookup('profile_cassandra_pfpt::disk_optimization_strategy', { 'default_value' => 'ssd' })
  $auto_snapshot                    = lookup('profile_cassandra_pfpt::auto_snapshot', { 'default_value' => true })
  $phi_convict_threshold            = lookup('profile_cassandra_pfpt::phi_convict_threshold', { 'default_value' => 8 })
  $concurrent_reads                 = lookup('profile_cassandra_pfpt::concurrent_reads', { 'default_value' => 32 })
  $concurrent_writes                = lookup('profile_cassandra_pfpt::concurrent_writes', { 'default_value' => 32 })
  $concurrent_counter_writes        = lookup('profile_cassandra_pfpt::concurrent_counter_writes', { 'default_value' => 32 })
  $memtable_allocation_type         = lookup('profile_cassandra_pfpt::memtable_allocation_type', { 'default_value' => 'heap_buffers' })
  $index_summary_capacity_in_mb     = lookup('profile_cassandra_pfpt::index_summary_capacity_in_mb', { 'default_value' => undef })
  $file_cache_size_in_mb            = lookup('profile_cassandra_pfpt::file_cache_size_in_mb', { 'default_value' => undef })
  $enable_materialized_views        = lookup('profile_cassandra_pfpt::enable_materialized_views', { 'default_value' => false })

  # Coralogix Settings
  $manage_coralogix_agent           = lookup('profile_cassandra_pfpt::manage_coralogix_agent', { 'default_value' => false })
  $coralogix_api_key                = lookup('profile_cassandra_pfpt::coralogix_api_key', { 'default_value' => '' })
  $coralogix_region                 = lookup('profile_cassandra_pfpt::coralogix_region', { 'default_value' => 'US' })
  $coralogix_logs_enabled           = lookup('profile_cassandra_pfpt::coralogix_logs_enabled', { 'default_value' => true })
  $coralogix_metrics_enabled        = lookup('profile_cassandra_pfpt::coralogix_metrics_enabled', { 'default_value' => true })

  # Calculate extra JVM args based on GC type and Java version
  $default_extra_jvm_args = if $gc_type == 'G1GC' and versioncmp($java_version, '14') < 0 {
    [
      '-XX:G1HeapRegionSize=16M',
      '-XX:MaxGCPauseMillis=500',
      '-XX:InitiatingHeapOccupancyPercent=75',
      '-XX:+ParallelRefProcEnabled',
      '-XX:+AggressiveOpts',
    ]
  } elsif $gc_type == 'CMS' and versioncmp($java_version, '14') < 0 {
    [
      '-XX:+UseConcMarkSweepGC',
      '-XX:+CMSParallelRemarkEnabled',
      '-XX:SurvivorRatio=8',
      '-XX:MaxTenuringThreshold=1',
      '-XX:CMSInitiatingOccupancyFraction=75',
      '-XX:+UseCMSInitiatingOccupancyOnly',
      '-XX:+CMSClassUnloadingEnabled',
      '-XX:+AlwaysPreTouch',
    ]
  } else {
    []
  }

  $extra_jvm_args = lookup('profile_cassandra_pfpt::extra_jvm_args', { 'default_value' => $default_extra_jvm_args })


  class { 'cassandra_pfpt':
    cassandra_version                => $cassandra_version,
    java_version                     => $java_version,
    java_package_name                => $java_package_name,
    manage_repo                      => $manage_repo,
    user                             => $user,
    group                            => $group,
    repo_baseurl                     => $repo_baseurl,
    repo_gpgkey                      => $repo_gpgkey,
    repo_gpgcheck                    => $repo_gpgcheck,
    repo_priority                    => $repo_priority,
    repo_skip_if_unavailable         => $repo_skip_if_unavailable,
    repo_sslverify                   => $repo_sslverify,
    package_dependencies             => $package_dependencies,
    cluster_name                     => $cluster_name,
    seeds                            => $seeds,
    listen_address                   => $listen_address,
    datacenter                       => $datacenter,
    rack                             => $rack,
    data_dir                         => $data_dir,
    commitlog_dir                    => $commitlog_dir,
    saved_caches_dir                 => $saved_caches_dir,
    hints_directory                  => $hints_directory,
    max_heap_size                    => $max_heap_size,
    gc_type                          => $gc_type,
    extra_jvm_args                   => $extra_jvm_args,
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
    use_shenandoah_gc                => $use_shenandoah_gc,
    racks                            => $racks,
    ssl_enabled                      => $ssl_enabled,
    https_domain                     => $https_domain,
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
    manage_jmx_security              => $manage_jmx_security,
    jmx_password_file_content        => $jmx_password_file_content,
    jmx_access_file_content          => $jmx_access_file_content,
    jmx_password_file_path           => $jmx_password_file_path,
    jmx_access_file_path             => $jmx_access_file_path,
    service_timeout_start_sec        => $service_timeout_start_sec,
    authorizer                       => $authorizer,
    authenticator                    => $authenticator,
    num_tokens                       => $num_tokens,
    native_transport_port            => $native_transport_port,
    endpoint_snitch                  => $endpoint_snitch,
    listen_interface                 => $listen_interface,
    rpc_interface                    => $rpc_interface,
    broadcast_address                => $broadcast_address,
    broadcast_rpc_address            => $broadcast_rpc_address,
    counter_cache_size_in_mb         => $counter_cache_size_in_mb,
    key_cache_size_in_mb             => $key_cache_size_in_mb,
    disk_optimization_strategy       => $disk_optimization_strategy,
    auto_snapshot                    => $auto_snapshot,
    phi_convict_threshold            => $phi_convict_threshold,
    concurrent_reads                 => $concurrent_reads,
    concurrent_writes                => $concurrent_writes,
    concurrent_counter_writes        => $concurrent_counter_writes,
    memtable_allocation_type         => $memtable_allocation_type,
    index_summary_capacity_in_mb     => $index_summary_capacity_in_mb,
    file_cache_size_in_mb            => $file_cache_size_in_mb,
    enable_materialized_views        => $enable_materialized_views,
    manage_coralogix_agent           => $manage_coralogix_agent,
    coralogix_api_key                => $coralogix_api_key,
    coralogix_region                 => $coralogix_region,
    coralogix_logs_enabled           => $coralogix_logs_enabled,
    coralogix_metrics_enabled        => $coralogix_metrics_enabled,
  }
}
        `.trim(),
    };




