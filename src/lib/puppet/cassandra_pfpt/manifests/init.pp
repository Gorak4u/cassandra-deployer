
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
  Boolean $manage_backups,
  String $full_backup_schedule,
  String $incremental_backup_schedule,
  String $backup_s3_bucket,
  String $full_backup_script_path,
  String $incremental_backup_script_path,
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
  if $manage_backups {
    class { 'cassandra_pfpt::backup':
      full_backup_schedule         => $full_backup_schedule,
      incremental_backup_schedule  => $incremental_backup_schedule,
      backup_s3_bucket             => $backup_s3_bucket,
      full_backup_script_path      => $full_backup_script_path,
      incremental_backup_script_path => $incremental_backup_script_path,
    }
  }
  Class['cassandra_pfpt::java']
  -> Class['cassandra_pfpt::install']
  -> Class['cassandra_pfpt::config']
  ~> Class['cassandra_pfpt::service']
}
        