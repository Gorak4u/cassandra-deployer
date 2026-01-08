
export const puppetCode = {
  root: {
    'metadata.json': 
      '{\n' +
      '  "name": "ggonda-cassandra",\n' +
      '  "version": "1.0.0",\n' +
      '  "author": "ggonda",\n' +
      '  "summary": "Production-ready Puppet profile to manage Apache Cassandra at scale.",\n' +
      '  "license": "Apache-2.0",\n' +
      '  "source": "https://github.com/ggonda/profile_ggonda_cassandra",\n' +
      '  "project_page": "https://github.com/ggonda/profile_ggonda_cassandra",\n' +
      '  "issues_url": "https://github.com/ggonda/profile_ggonda_cassandra/issues",\n' +
      '  "dependencies": [\n' +
      '    {\n' +
      '      "name": "puppetlabs/stdlib",\n' +
      '      "version_requirement": ">= 6.0.0 < 9.0.0"\n' +
      '    },\n' +
      '    {\n' +
      '      "name": "puppetlabs/apt",\n' +
      '      "version_requirement": ">= 7.0.0 < 9.0.0"\n' +
      '    }\n' +
      '  ],\n' +
      '  "operatingsystem_support": [\n' +
      '    {\n' +
      '      "operatingsystem": "RedHat",\n' +
      '      "operatingsystemrelease": [ "7", "8" ]\n' +
      '    },\n' +
      '    {\n' +
      '      "operatingsystem": "CentOS",\n' +
      '      "operatingsystemrelease": [ "7", "8" ]\n' +
      '    },\n' +
      '    {\n' +
      '      "operatingsystem": "Debian",\n' +
      '      "operatingsystemrelease": [ "9", "10", "11" ]\n' +
      '    },\n' +
      '    {\n' +
      '      "operatingsystem": "Ubuntu",\n' +
      '      "operatingsystemrelease": [ "18.04", "20.04", "22.04" ]\n' +
      '    }\n' +
      '  ],\n' +
      '  "requirements": [\n' +
      '    {\n' +
      '      "name": "puppet",\n' +
      '      "version_requirement": ">= 6.0.0 < 8.0.0"\n' +
      '    }\n' +
      '  ]\n' +
      '}'
    ,
  },
  manifests: {
    'init.pp': 
      '# @summary Main entry point for the Cassandra profile.\n' +
      '# @param version The version of Cassandra to install.\n' +
      '# @param seeds An array of seed node IP addresses.\n' +
      '# @param authenticator The authentication backend to use.\n' +
      '# @param authorizer The authorization backend to use.\n' +
      '# @param client_encryption_enabled Enable/disable client-to-node TLS.\n' +
      '# @param server_encryption_enabled Enable/disable node-to-node TLS.\n' +
      'class cassandra (\n' +
      "  String \\$version                                  = '4.1.3',\n" +
      "  String \\$package_name                              = 'cassandra',\n" +
      "  String \\$service_name                              = 'cassandra',\n" +
      "  String \\$config_dir                                = '/etc/cassandra',\n" +
      "  Optional[String] \\$java_package_name               = undef,\n" +
      '\n' +
      '  # cassandra.yaml - Basic Settings\n' +
      "  String \\$cluster_name                              = 'MyCassandraCluster',\n" +
      "  Array[Stdlib::IP::Address] \\$seeds                  = [\\$facts['networking']['ip']],\n" +
      "  String \\$listen_address                            = \\$facts['networking']['ip'],\n" +
      "  String \\$rpc_address                               = \\$facts['networking']['ip'],\n" +
      "  Integer \\$num_tokens                               = 256,\n" +
      "  String \\$endpoint_snitch                           = 'GossipingPropertyFileSnitch',\n" +
      '\n' +
      '  # cassandra.yaml - Directories\n' +
      "  Array[String] \\$data_file_directories              = ['/var/lib/cassandra/data'],\n" +
      "  String \\$commitlog_directory                       = '/var/lib/cassandra/commitlog',\n" +
      "  String \\$saved_caches_directory                   = '/var/lib/cassandra/saved_caches',\n" +
      '\n' +
      '  # cassandra.yaml - Security Settings\n' +
      "  String \\$authenticator                             = 'AllowAllAuthenticator',\n" +
      "  String \\$authorizer                                = 'AllowAllAuthorizer',\n" +
      '  Boolean \\$client_encryption_enabled                = false,\n' +
      "  String \\$client_encryption_keystore                = 'conf/.keystore',\n" +
      "  String \\$client_encryption_truststore              = 'conf/.truststore',\n" +
      '  Boolean \\$server_encryption_enabled                = false,\n' +
      "  String \\$server_encryption_keystore                = 'conf/.keystore',\n" +
      "  String \\$server_encryption_truststore              = 'conf/.truststore',\n" +
      '\n' +
      '  # cassandra.yaml - Performance Tuning\n' +
      "  Integer \\$concurrent_reads                         = 32,\n" +
      "  Integer \\$concurrent_writes                        = 64,\n" +
      "  Integer \\$concurrent_counter_writes                 = 32,\n" +
      "  Integer \\$concurrent_compactors                     = 4,\n" +
      "  Integer \\$memtable_flush_writers                    = 4,\n" +
      "  Integer \\$compaction_throughput_mb_per_sec          = 64,\n" +
      "  Integer \\$in_memory_compaction_limit_in_mb          = 256,\n" +
      "  Integer \\$tombstone_warn_threshold                  = 10000,\n" +
      "  String \\$read_request_timeout_in_ms                = '5000',\n" +
      "  String \\$write_request_timeout_in_ms               = '5000',\n" +
      "  String \\$cas_contention_timeout_in_ms              = '2500',\n" +
      '\n' +
      '  # cassandra-env.sh / jvm.options - JVM Settings\n' +
      "  Optional[String] \\$jvm_max_heap_size                = undef, # e.g. '4G' or '8192M'\n" +
      "  Optional[String] \\$jvm_new_heap_size                = undef, # e.g. '800M'\n" +
      "  Optional[String] \\$jvm_extra_opts                   = undef, # e.g. '-Djava.rmi.server.hostname=<hostname>'\n" +
      '  Boolean \\$use_java11                                = false,\n' +
      '  Boolean \\$use_g1_gc                                 = true,\n' +
      '  Boolean \\$use_shenandoah_gc                         = false,\n' +
      '\n' +
      '  # Rack and DC configuration\n' +
      '  Hash \\$racks                                      = {},\n' +
      '\n' +
      '  # System Tuning\n' +
      "  Boolean \\$manage_sysctl                             = true,\n" +
      "  String \\$net_ipv4_tcp_rmem                          = '4096 87380 16777216',\n" +
      "  String \\$net_ipv4_tcp_wmem                          = '4096 65536 16777216',\n" +
      "  Integer \\$net_core_rmem_max                         = 16777216,\n" +
      "  Integer \\$net_core_wmem_max                         = 16777216,\n" +
      "  Boolean \\$manage_limits                             = true,\n" +
      "  String \\$limits_memlock                            = 'unlimited',\n" +
      "  Integer \\$limits_nofile                             = 100000,\n" +
      "  Integer \\$limits_nproc                              = 32768,\n" +
      "  String \\$limits_as                                 = 'unlimited',\n" +
      '\n' +
      ') {\n' +
      "  if \\$facts['gce'] {\n" +
      "    \\$dc = \\$facts['gce']['instance']['zone']\n" +
      "    \\$zone = \\$facts['gce']['instance']['zone']\n" +
      '\n' +
      '    if \\$racks[\\$dc] {\n' +
      '      if \\$racks[\\$dc][\\$zone] {\n' +
      '        \\$rack = \\$racks[\\$dc][\\$zone]\n' +
      '      } else {\n' +
      "        \\$rack = 'rack1'\n" +
      '      }\n' +
      '    } else {\n' +
      "      \\$rack = 'rack1'\n" +
      '    }\n' +
      '  } else {\n' +
      "    \\$dc = 'dc1'\n" +
      "    \\$rack = 'rack1'\n" +
      '  }\n' +
      '\n' +
      '  contain cassandra::params\n' +
      '  contain cassandra::java\n' +
      '  contain cassandra::install\n' +
      '  contain cassandra::config\n' +
      '  contain cassandra::service\n' +
      '\n' +
      "  Class['cassandra::params']\n" +
      "  -> Class['cassandra::java']\n" +
      "  -> Class['cassandra::install']\n" +
      "  -> Class['cassandra::config']\n" +
      "  ~> Class['cassandra::service']\n" +
      '}'
    ,
    'params.pp': 
      '# @summary Namespaces all parameters for the Cassandra profile.\n' +
      'class cassandra::params {\n' +
      '  \\$version                  = \\$cassandra::version\n' +
      '  \\$package_name             = \\$cassandra::package_name\n' +
      '  \\$service_name             = \\$cassandra::service_name\n' +
      '  \\$config_dir               = \\$cassandra::config_dir\n' +
      '  \\$java_package_name        = \\$cassandra::java_package_name\n' +
      '\n' +
      '  # Basic Settings\n' +
      '  \\$cluster_name             = \\$cassandra::cluster_name\n' +
      '  \\$seeds                    = \\$cassandra::seeds\n' +
      '  \\$listen_address           = \\$cassandra::listen_address\n' +
      '  \\$rpc_address              = \\$cassandra::rpc_address\n' +
      '  \\$num_tokens               = \\$cassandra::num_tokens\n' +
      '  \\$endpoint_snitch          = \\$cassandra::endpoint_snitch\n' +
      '\n' +
      '  # Directories\n' +
      '  \\$data_file_directories    = \\$cassandra::data_file_directories\n' +
      '  \\$commitlog_directory      = \\$cassandra::commitlog_directory\n' +
      '  \\$saved_caches_directory   = \\$cassandra::saved_caches_directory\n' +
      '\n' +
      '  # Security Settings\n' +
      '  \\$authenticator            = \\$cassandra::authenticator\n' +
      '  \\$authorizer               = \\$cassandra::authorizer\n' +
      '  \\$client_encryption_enabled = \\$cassandra::client_encryption_enabled\n' +
      '  \\$client_encryption_keystore = \\$cassandra::client_encryption_keystore\n' +
      '  \\$client_encryption_truststore = \\$cassandra::client_encryption_truststore\n' +
      '  \\$server_encryption_enabled = \\$cassandra::server_encryption_enabled\n' +
      '  \\$server_encryption_keystore = \\$cassandra::server_encryption_keystore\n' +
      '  \\$server_encryption_truststore = \\$cassandra::server_encryption_truststore\n' +
      '\n' +
      '  # Performance Tuning\n' +
      '  \\$concurrent_reads        = \\$cassandra::concurrent_reads\n' +
      '  \\$concurrent_writes       = \\$cassandra::concurrent_writes\n' +
      '  \\$concurrent_counter_writes = \\$cassandra::concurrent_counter_writes\n' +
      '  \\$concurrent_compactors     = \\$cassandra::concurrent_compactors\n' +
      '  \\$memtable_flush_writers    = \\$cassandra::memtable_flush_writers\n' +
      '  \\$compaction_throughput_mb_per_sec = \\$cassandra::compaction_throughput_mb_per_sec\n' +
      '  \\$in_memory_compaction_limit_in_mb = \\$cassandra::in_memory_compaction_limit_in_mb\n' +
      '  \\$tombstone_warn_threshold  = \\$cassandra::tombstone_warn_threshold\n' +
      '  \\$read_request_timeout_in_ms = \\$cassandra::read_request_timeout_in_ms\n' +
      '  \\$write_request_timeout_in_ms = \\$cassandra::write_request_timeout_in_ms\n' +
      '  \\$cas_contention_timeout_in_ms = \\$cassandra::cas_contention_timeout_in_ms\n' +
      '\n' +
      '  # JVM Settings\n' +
      '  \\$jvm_max_heap_size        = \\$cassandra::jvm_max_heap_size\n' +
      '  \\$jvm_new_heap_size        = \\$cassandra::jvm_new_heap_size\n' +
      '  \\$jvm_extra_opts           = \\$cassandra::jvm_extra_opts\n' +
      '  \\$use_java11               = \\$cassandra::use_java11\n' +
      '  \\$use_g1_gc                = \\$cassandra::use_g1_gc\n' +
      '  \\$use_shenandoah_gc        = \\$cassandra::use_shenandoah_gc\n' +
      '\n' +
      '  # Rack and DC\n' +
      '  \\$dc                       = \\$cassandra::dc\n' +
      '  \\$rack                     = \\$cassandra::rack\n' +
      '\n' +
      '  # System Tuning\n' +
      '  \\$manage_sysctl             = \\$cassandra::manage_sysctl\n' +
      '  \\$net_ipv4_tcp_rmem          = \\$cassandra::net_ipv4_tcp_rmem\n' +
      '  \\$net_ipv4_tcp_wmem          = \\$cassandra::net_ipv4_tcp_wmem\n' +
      '  \\$net_core_rmem_max         = \\$cassandra::net_core_rmem_max\n' +
      '  \\$net_core_wmem_max         = \\$cassandra::net_core_wmem_max\n' +
      '  \\$manage_limits             = \\$cassandra::manage_limits\n' +
      '  \\$limits_memlock            = \\$cassandra::limits_memlock\n' +
      '  \\$limits_nofile             = \\$cassandra::limits_nofile\n' +
      '  \\$limits_nproc              = \\$cassandra::limits_nproc\n' +
      '  \\$limits_as                 = \\$cassandra::limits_as\n' +
      '}'
    ,
    'java.pp': 
      '# @summary Installs Java, a dependency for Cassandra.\n' +
      'class cassandra::java {\n' +
      '  \\$java_package_name = \\$cassandra::params::java_package_name\n' +
      '  \\$use_java11 = \\$cassandra::params::use_java11\n' +
      '\n' +
      '  # Determine the default Java package based on the OS family and version flag\n' +
      '  if \\$use_java11 {\n' +
      "    \\$default_java_package = \\$facts['os']['family'] ? {\n" +
      "      'RedHat' => 'java-11-openjdk-headless',\n" +
      "      'Debian' => 'openjdk-11-jre-headless',\n" +
      "      default  => fail(\\\"Unsupported OS family for Java 11 installation: \${facts['os']['family']}\\\"),\n" +
      '    }\n' +
      '  } else {\n' +
      "    \\$default_java_package = \\$facts['os']['family'] ? {\n" +
      "      'RedHat' => 'java-1.8.0-openjdk-headless',\n" +
      "      'Debian' => 'openjdk-8-jre-headless',\n" +
      "      default  => fail(\\\"Unsupported OS family for Java 8 installation: \${facts['os']['family']}\\\"),\n" +
      '    }\n' +
      '  }\n' +
      '\n' +
      '  # Use the Hiera-provided package name if it exists, otherwise use the default\n' +
      '  \\$package_to_install = pick(\\$java_package_name, \\$default_java_package)\n' +
      '\n' +
      "  package { 'java-for-cassandra':\n" +
      '    ensure => installed,\n' +
      '    name   => \\$package_to_install,\n' +
      '  }\n' +
      '}'
    ,
    'install.pp': 
      '# @summary Installs the Cassandra package.\n' +
      'class cassandra::install {\n' +
      '  \\$package_name = \\$cassandra::params::package_name\n' +
      '  \\$version = \\$cassandra::params::version\n' +
      '\n' +
      "  \\$version_major_only = regsubst(\\$version, '^(\\\\d)\\\\.(\\\\d)\\\\..*', '\\\\1\\\\2')\n" +
      '\n' +
      "  case \\$facts['os']['family'] {\n" +
      "    'RedHat': {\n" +
      "      yumrepo { 'cassandra':\n" +
      "        ensure   => 'present',\n" +
      "        descr    => \\\"Apache Cassandra \${version_major_only}x repo\\\",\n" +
      "        baseurl  => \\\"https://downloads.apache.org/cassandra/redhat/\${version_major_only}x/\\\",\n" +
      '        enabled  => 1,\n' +
      '        gpgcheck => 0, # For production, set to 1 and manage the key\n' +
      '      }\n' +
      "      Yumrepo['cassandra'] -> Package[\\$package_name]\n" +
      '    }\n' +
      "    'Debian': {\n" +
      "      apt::source { 'cassandra':\n" +
      "        location => 'https://downloads.apache.org/cassandra/debian',\n" +
      "        release  => \\\"\${version_major_only}x\\\",\n" +
      "        repos    => 'main',\n" +
      '        key      => {\n' +
      "          id     => 'F758CE318D77295D',\n" +
      "          source => 'https://downloads.apache.org/cassandra/KEYS',\n" +
      '        },\n' +
      '      }\n' +
      "      Apt::Source['cassandra'] -> Package[\\$package_name]\n" +
      '    }\n' +
      '    default: {\n' +
      "      fail(\\\"Cassandra installation is not supported on OS family '\${facts['os']['family']}'\\\")\n" +
      '    }\n' +
      '  }\n' +
      '\n' +
      '  package { \\$package_name:\n' +
      '    ensure  => \\$version,\n' +
      "    require => Class['cassandra::java'],\n" +
      '  }\n' +
      '}'
    ,
    'config.pp': 
      '# @summary Manages Cassandra configuration files.\n' +
      'class cassandra::config {\n' +
      '  \\$config_dir = \\$cassandra::params::config_dir\n' +
      '  \\$config_file = "\\${config_dir}/cassandra.yaml"\n' +
      '  \\$env_file = "\\${config_dir}/cassandra-env.sh"\n' +
      '  \\$jvm_options_file = "\\${config_dir}/jvm-server.options"\n' +
      '  \\$rack_dc_file = "\\${config_dir}/cassandra-rackdc.properties"\n' +
      '  \\$limits_file = "/etc/security/limits.d/cassandra.conf"\n' +
      '  \\$sysctl_file = "/etc/sysctl.d/90-cassandra.conf"\n' +
      "  \\$owner = 'cassandra'\n" +
      "  \\$group = 'cassandra'\n" +
      '\n' +
      "  \\$seeds_string = join(\\$cassandra::params::seeds, ',')\n" +
      '\n' +
      '  file { \\$config_file:\n' +
      '    ensure  => file,\n' +
      '    owner   => \\$owner,\n' +
      '    group   => \\$group,\n' +
      "    mode    => '0640',\n" +
      "    content => template('cassandra/cassandra.yaml.erb'),\n" +
      '    require => Package[\\$cassandra::params::package_name],\n' +
      '  }\n' +
      '\n' +
      '  file { \\$env_file:\n' +
      '    ensure  => file,\n' +
      '    owner   => \\$owner,\n' +
      '    group   => \\$group,\n' +
      "    mode    => '0640',\n" +
      "    content => template('cassandra/cassandra-env.sh.erb'),\n" +
      '    require => Package[\\$cassandra::params::package_name],\n' +
      '  }\n' +
      '\n' +
      '  file { \\$jvm_options_file:\n' +
      '    ensure  => file,\n' +
      '    owner   => \\$owner,\n' +
      '    group   => \\$group,\n' +
      "    mode    => '0644',\n" +
      "    content => template('cassandra/jvm-server.options.erb'),\n" +
      '    require => Package[\\$cassandra::params::package_name],\n' +
      '  }\n' +
      '\n' +
      '  file { \\$rack_dc_file:\n' +
      '    ensure  => file,\n' +
      '    owner   => \\$owner,\n' +
      '    group   => \\$group,\n' +
      "    mode    => '0644',\n" +
      "    content => template('cassandra/cassandra-rackdc.properties.erb'),\n" +
      '    require => Package[\\$cassandra::params::package_name],\n' +
      '  }\n' +
      '\n' +
      '  if \\$cassandra::params::manage_limits {\n' +
      '    file { \\$limits_file:\n' +
      '      ensure  => file,\n' +
      "      owner   => 'root',\n" +
      "      group   => 'root',\n" +
      "      mode    => '0644',\n" +
      "      content => template('cassandra/cassandra_limits.conf.erb'),\n" +
      '    }\n' +
      '  }\n' +
      '\n' +
      '  if \\$cassandra::params::manage_sysctl {\n' +
      '    file { \\$sysctl_file:\n' +
      '      ensure  => file,\n' +
      "      owner   => 'root',\n" +
      "      group   => 'root',\n" +
      "      mode    => '0644',\n" +
      "      content => template('cassandra/sysctl.conf.erb'),\n" +
      '      notify  => Exec[\'apply-cassandra-sysctl\'],\n' +
      '    }\n' +
      '\n' +
      "    exec { 'apply-cassandra-sysctl':\n" +
      "      command     => 'sysctl --system',\n" +
      '      refreshonly => true,\n' +
      '    }\n' +
      '  }\n' +
      '\n' +
      '  # Ensure data directories exist with correct permissions\n' +
      '  [ \\$cassandra::params::data_file_directories,\n' +
      '    \\$cassandra::params::commitlog_directory,\n' +
      '    \\$cassandra::params::saved_caches_directory,\n' +
      '  ].flatten.each |String \\$dir| {\n' +
      '    file { \\$dir:\n' +
      '      ensure  => directory,\n' +
      '      owner   => \\$owner,\n' +
      '      group   => \\$group,\n' +
      "      mode    => '0750',\n" +
      '      require => Package[\\$cassandra::params::package_name],\n' +
      '    }\n' +
      '  }\n' +
      '}'
    ,
    'service.pp': 
      '# @summary Manages the Cassandra service.\n' +
      'class cassandra::service {\n' +
      '  \\$service_name = \\$cassandra::params::service_name\n' +
      '\n' +
      '  service { \\$service_name:\n' +
      '    ensure    => running,\n' +
      '    enable    => true,\n' +
      '    hasstatus => true,\n' +
      '  }\n' +
      '}'
    ,
  },
  templates: {
    'cassandra.yaml.erb': 
      '# cassandra.yaml\n' +
      '# Generated by Puppet from cassandra/cassandra.yaml.erb. DO NOT EDIT.\n' +
      '\n' +
      "cluster_name: '<%= @cassandra::params::cluster_name %>'\n" +
      'num_tokens: <%= @cassandra::params::num_tokens %>\n' +
      '\n' +
      '# Seed provider\n' +
      'seed_provider:\n' +
      '  - class_name: org.apache.cassandra.locator.SimpleSeedProvider\n' +
      '    parameters:\n' +
      '      - seeds: "<%= @seeds_string %>"\n' +
      '\n' +
      'listen_address: <%= @cassandra::params::listen_address %>\n' +
      'rpc_address: <%= @cassandra::params::rpc_address %>\n' +
      '\n' +
      'endpoint_snitch: <%= @cassandra::params::endpoint_snitch %>\n' +
      '\n' +
      '# Data directories\n' +
      'data_file_directories:\n' +
      '<% @cassandra::params::data_file_directories.each do |dir| -%>\n' +
      '  - <%= dir %>\n' +
      '<% end -%>\n' +
      '\n' +
      'commitlog_directory: <%= @cassandra::params::commitlog_directory %>\n' +
      'saved_caches_directory: <%= @cassandra::params::saved_caches_directory %>\n' +
      'commitlog_sync: periodic\n' +
      'commitlog_sync_period_in_ms: 10000\n' +
      '\n' +
      '# Performance Tuning\n' +
      'concurrent_reads: <%= @cassandra::params::concurrent_reads %>\n' +
      'concurrent_writes: <%= @cassandra::params::concurrent_writes %>\n' +
      'concurrent_counter_writes: <%= @cassandra::params::concurrent_counter_writes %>\n' +
      'concurrent_compactors: <%= @cassandra::params::concurrent_compactors %>\n' +
      'memtable_flush_writers: <%= @cassandra::params::memtable_flush_writers %>\n' +
      'compaction_throughput_mb_per_sec: <%= @cassandra::params::compaction_throughput_mb_per_sec %>\n' +
      'in_memory_compaction_limit_in_mb: <%= @cassandra::params::in_memory_compaction_limit_in_mb %>\n' +
      'tombstone_warn_threshold: <%= @cassandra::params::tombstone_warn_threshold %>\n' +
      '\n' +
      '# Timeouts\n' +
      'read_request_timeout_in_ms: <%= @cassandra::params::read_request_timeout_in_ms %>\n' +
      'write_request_timeout_in_ms: <%= @cassandra::params::write_request_timeout_in_ms %>\n' +
      'cas_contention_timeout_in_ms: <%= @cassandra::params::cas_contention_timeout_in_ms %>\n' +
      '\n' +
      '# Security\n' +
      'authenticator: <%= @cassandra::params::authenticator %>\n' +
      'authorizer: <%= @cassandra::params::authorizer %>\n' +
      '\n' +
      '# Client-to-Node Encryption\n' +
      'client_encryption_options:\n' +
      '  enabled: <%= @cassandra::params::client_encryption_enabled %>\n' +
      '<% if @cassandra::params::client_encryption_enabled -%>\n' +
      '  keystore: <%= @cassandra::params::client_encryption_keystore %>\n' +
      '  keystore_password: "CHANGEME"\n' +
      '  truststore: <%= @cassandra::params::client_encryption_truststore %>\n' +
      '  truststore_password: "CHANGEME"\n' +
      '<% end -%>\n' +
      '\n' +
      '# Node-to-Node Encryption\n' +
      'server_encryption_options:\n' +
      '  internode_encryption: <%= @cassandra::params::server_encryption_enabled ? "all" : "none" %>\n' +
      '<% if @cassandra::params::server_encryption_enabled -%>\n' +
      '  keystore: <%= @cassandra::params::server_encryption_keystore %>\n' +
      '  keystore_password: "CHANGEME"\n' +
      '  truststore: <%= @cassandra::params::server_encryption_truststore %>\n' +
      '  truststore_password: "CHANGEME"\n' +
      '<% end -%>'
    ,
    'cassandra-env.sh.erb': 
      '#!/bin/sh\n' +
      '# This file is managed by Puppet from cassandra/cassandra-env.sh.erb.\n' +
      '# Local changes will be overwritten.\n' +
      '#\n' +
      '\n' +
      '# Set Java Heap Size\n' +
      '<% if @cassandra::params::jvm_max_heap_size -%>\n' +
      'MAX_HEAP_SIZE="<%= @cassandra::params::jvm_max_heap_size %>"\n' +
      '<% end -%>\n' +
      '<% if @cassandra::params::jvm_new_heap_size -%>\n' +
      'HEAP_NEWSIZE="<%= @cassandra::params::jvm_new_heap_size %>"\n' +
      '<% end -%>\n' +
      '\n' +
      '# Add extra JVM options\n' +
      '<% if @cassandra::params::jvm_extra_opts -%>\n' +
      'JVM_EXTRA_OPTS="$JVM_EXTRA_OPTS <%= @cassandra::params::jvm_extra_opts %>"\n' +
      '<% end -%>\n' +
      '\n' +
      '# Use G1GC for modern garbage collection\n' +
      '# This is a sensible default for most workloads on modern hardware\n' +
      'if [ "$JVM_VENDOR" = "OpenJDK" ] && [ "$JVM_VERSION" -ge 7 ]; then\n' +
      '  CASSANDRA_GC_OPTS="-XX:+UseG1GC -XX:G1RSetUpdatingPauseTimePercent=5 -XX:MaxGCPauseMillis=500"\n' +
      'fi\n' +
      'export CASSANDRA_GC_OPTS\n' +
      ''
    ,
    'jvm-server.options.erb': 
      '# jvm-server.options\n' +
      '# Generated by Puppet from cassandra/jvm-server.options.erb\n' +
      '# This file is for Cassandra 4.x and later.\n' +
      '\n' +
      '# Basic memory settings\n' +
      '<% if @cassandra::params::jvm_max_heap_size -%>\n' +
      '-Xms<%= @cassandra::params::jvm_max_heap_size %>\n' +
      '-Xmx<%= @cassandra::params::jvm_max_heap_size %>\n' +
      '<% else -%>\n' +
      '# Default if not set in Hiera\n' +
      '-Xms4G\n' +
      '-Xmx4G\n' +
      '<% end -%>\n' +
      '\n' +
      '# GC Settings\n' +
      '<% if @cassandra::params::use_shenandoah_gc -%>\n' +
      '-XX:+UseShenandoahGC\n' +
      '-XX:+UnlockExperimentalVMOptions\n' +
      '<% elsif @cassandra::params::use_g1_gc -%>\n' +
      '-XX:+UseG1GC\n' +
      '-XX:G1RSetUpdatingPauseTimePercent=5\n' +
      '-XX:MaxGCPauseMillis=500\n' +
      '<% else -%>\n' +
      '-XX:+UseConcMarkSweepGC\n' +
      '-XX:+CMSParallelRemarkEnabled\n' +
      '<% end -%>\n' +
      '\n' +
      '# Other standard options\n' +
      '-XX:+HeapDumpOnOutOfMemoryError\n' +
      '-XX:HeapDumpPath=/var/lib/cassandra/java_pid<pid>.hprof\n' +
      '-Dcassandra.jmx.local.port=7199\n' +
      '-Dcom.sun.management.jmxremote.authenticate=false\n' +
      '-Dcom.sun.management.jmxremote.ssl=false\n' +
      ''
    ,
    'cassandra-rackdc.properties.erb': 
      '# cassandra-rackdc.properties\n' +
      '# Generated by Puppet\n' +
      '# Used by GossipingPropertyFileSnitch\n' +
      'dc=<%= @cassandra::params::dc %>\n' +
      'rack=<%= @cassandra::params::rack %>\n'
    ,
    'cassandra_limits.conf.erb': 
      '# /etc/security/limits.d/cassandra.conf\n' +
      '# Generated by Puppet\n' +
      'cassandra - memlock <%= @cassandra::params::limits_memlock %>\n' +
      'cassandra - nofile <%= @cassandra::params::limits_nofile %>\n' +
      'cassandra - nproc <%= @cassandra::params::limits_nproc %>\n' +
      'cassandra - as <%= @cassandra::params::limits_as %>\n' +
      'root - memlock <%= @cassandra::params::limits_memlock %>\n' +
      'root - nofile <%= @cassandra::params::limits_nofile %>\n' +
      'root - nproc <%= @cassandra::params::limits_nproc %>\n' +
      'root - as <%= @cassandra::params::limits_as %>\n'
    ,
    'sysctl.conf.erb':
      '# /etc/sysctl.d/90-cassandra.conf\n' +
      '# Generated by Puppet for Cassandra tuning\n' +
      '\n' +
      '# Network settings\n' +
      'net.ipv4.tcp_rmem = <%= @cassandra::params::net_ipv4_tcp_rmem %>\n' +
      'net.ipv4.tcp_wmem = <%= @cassandra::params::net_ipv4_tcp_wmem %>\n' +
      'net.core.rmem_max = <%= @cassandra::params::net_core_rmem_max %>\n' +
      'net.core.wmem_max = <%= @cassandra::params::net_core_wmem_max %>\n' +
      '\n' +
      '# Other recommendations\n' +
      'vm.max_map_count = 1048575\n'
  },
  scripts: {
    'robust_backup.sh': 
      '#!/bin/bash\n' +
      '# Robust backup script for a Cassandra node. Manages snapshots and optionally uploads to cloud storage.\n' +
      'set -e\n' +
      '\n' +
      '# --- Configuration ---\n' +
      'KEYSPACE="${1:-my_keyspace}" # Pass keyspace as first argument, or default\n' +
      'BACKUP_BASE_DIR="/var/backups/cassandra"\n' +
      'SNAPSHOT_NAME="snapshot_$(date +%Y-%m-%d_%H-%M-%S)"\n' +
      'BACKUP_DIR="${BACKUP_BASE_DIR}/${KEYSPACE}/${SNAPSHOT_NAME}"\n' +
      'DATADIR="/var/lib/cassandra/data"\n' +
      '# Set to true to upload to a cloud bucket (e.g., S3, GCS)\n' +
      'UPLOAD_TO_CLOUD=false\n' +
      'CLOUD_BUCKET_PATH="s3://my-cassandra-backups/"\n' +
      'LOG_FILE="/var/log/cassandra/backup.log"\n' +
      '\n' +
      '# --- Logging ---\n' +
      'log() {\n' +
      '  echo "$(date) - $1" | tee -a $LOG_FILE\n' +
      '  }\n' +
      '\n' +
      '# --- Main Logic ---\n' +
      'log "Starting backup for keyspace: ${KEYSPACE}"\n' +
      '\n' +
      'log "Creating snapshot ${SNAPSHOT_NAME}..."\n' +
      'nodetool snapshot -t "${SNAPSHOT_NAME}" "${KEYSPACE}"\n' +
      'log "Snapshot created successfully."\n' +
      '\n' +
      'log "Copying snapshot files to ${BACKUP_DIR}..."\n' +
      'mkdir -p "${BACKUP_DIR}"\n' +
      'find "${DATADIR}/${KEYSPACE}" -type d -path "*/snapshots/${SNAPSHOT_NAME}" -exec rsync -a --no-o --no-g {}/ "${BACKUP_DIR}" \\;\n' +
      'log "Snapshot files copied."\n' +
      '\n' +
      'if [ "$UPLOAD_TO_CLOUD" = true ]; then\n' +
      '  log "Uploading backup to ${CLOUD_BUCKET_PATH}..."\n' +
      '  # Add your cloud CLI command here, e.g.:\n' +
      '  # aws s3 sync "${BACKUP_DIR}" "${CLOUD_BUCKET_PATH}${KEYSPACE}/${SNAPSHOT_NAME}/"\n' +
      '  log "Cloud upload complete."\n' +
      'fi\n' +
      '\n' +
      'log "Clearing snapshot ${SNAPSHOT_NAME}..."\n' +
      'nodetool clearsnapshot -t "${SNAPSHOT_NAME}" "${KEYSPACE}"\n' +
      'log "Snapshot cleared."\n' +
      '\n' +
      'log "Backup complete for keyspace: ${KEYSPACE}"\n' +
      ''
    ,
    'restore_from_backup.sh': 
      '#!/bin/bash\n' +
      '# Script to restore a Cassandra keyspace from a snapshot backup.\n' +
      'set -e\n' +
      '\n' +
      '# --- Configuration ---\n' +
      'KEYSPACE="${1:?Please provide a keyspace to restore.}"\n' +
      'BACKUP_PATH="${2:?Please provide the full path to the backup directory.}"\n' +
      'DATADIR="/var/lib/cassandra/data"\n' +
      '\n' +
      'echo "WARNING: This will stop Cassandra and replace data for keyspace ${KEYSPACE}."\n' +
      'read -p "Are you sure you want to continue? (y/N) " -n 1 -r\n' +
      'echo\n' +
      'if [[ ! $REPLY =~ ^[Yy]$ ]]\n' +
      'then\n' +
      '    exit 1\n' +
      'fi\n' +
      '\n' +
      'echo "Stopping Cassandra..."\n' +
      'systemctl stop cassandra\n' +
      '\n' +
      'echo "Clearing old data for keyspace ${KEYSPACE}..."\n' +
      'find "${DATADIR}/${KEYSPACE}" -mindepth 1 -maxdepth 1 -type d -exec rm -rf {} +\n' +
      '\n' +
      'echo "Restoring data from ${BACKUP_PATH}..."\n' +
      '# Find the table directories in the backup\n' +
      'for table_dir in "${BACKUP_PATH}"/*/; do\n' +
      '  table_name=$(basename "$table_dir")\n' +
      '  target_dir="${DATADIR}/${KEYSPACE}/${table_name}-*/"\n' +
      '  if [ -d $target_dir ]; then\n' +
      '    echo "  - Restoring ${table_name}"\n' +
      '    rsync -a --no-o --no-g "${table_dir}" "${target_dir}"\n' +
      '  else\n' +
      '    echo "  - WARNING: Could not find target directory for table ${table_name}"\n' +
      '  fi\n' +
      'done\n' +
      '\n' +
      'echo "Fixing permissions..."\n' +
      'chown -R cassandra:cassandra "${DATADIR}/${KEYSPACE}"\n' +
      '\n' +
      'echo "Starting Cassandra..."\n' +
      'systemctl start cassandra\n' +
      '\n' +
      'echo "Waiting for node to come up..."\n' +
      'sleep 30 # Adjust as needed\n' +
      '\n' +
      'echo "Running nodetool refresh for keyspace ${KEYSPACE}..."\n' +
      'nodetool refresh "${KEYSPACE}"\n' +
      '\n' +
      'echo "Restore complete. Remember to run a full repair on the cluster."\n' +
      ''
    ,
    'node_health_check.sh': 
      '#!/bin/bash\n' +
      '# Performs a basic health check on the local Cassandra node.\n' +
      '\n' +
      'echo "--- Node Status ---"\n' +
      'nodetool status\n' +
      'echo\n' +
      '\n' +
      'echo "--- Gossip Info ---"\n' +
      'nodetool gossipinfo\n' +
      'echo\n' +
      '\n' +
      'echo "--- Ring Status ---"\n' +
      'nodetool ring\n' +
      'echo\n' +
      '\n' +
      'echo "--- Effective Ownership ---"\n' +
      'nodetool describecluster\n' +
      'echo\n' +
      '\n' +
      'echo "Health check complete. Review output for any issues (e.g., nodes in DN status)."\n' +
      ''
    ,
    'rolling_restart.sh': 
      '#!/bin/bash\n' +
      '# Performs a rolling restart of a Cassandra cluster.\n' +
      '# This script should be run from one of the Cassandra nodes.\n' +
      'set -e\n' +
      '\n' +
      '# --- Configuration ---\n' +
      '# List of all node IPs in the cluster\n' +
      'ALL_NODES=("10.0.1.10" "10.0.1.11" "10.0.1.12" "10.0.1.13")\n' +
      'SSH_USER="admin"\n' +
      'WAIT_TIME=60 # Seconds to wait between node restarts\n' +
      '\n' +
      'log() {\n' +
      '  echo "[$(date)] - $1"\n' +
      '}\n' +
      '\n' +
      'log "Starting rolling restart of the Cassandra cluster..."\n' +
      '\n' +
      'for node in "${ALL_NODES[@]}"; do\n' +
      '  log "--- Processing node: ${node} ---"\n' +
      '\n' +
      '  log "Draining node ${node}..."\n' +
      '  ssh "${SSH_USER}@${node}" "nodetool drain"\n' +
      '  if [ $? -ne 0 ]; then\n' +
      '    log "ERROR: Failed to drain node ${node}. Aborting restart."\n' +
      '    exit 1\n' +
      '  fi\n' +
      '\n' +
      '  log "Stopping Cassandra service on ${node}..."\n' +
      '  ssh "${SSH_USER}@${node}" "sudo systemctl stop cassandra"\n' +
      '\n' +
      '  log "Starting Cassandra service on ${node}..."\n' +
      '  ssh "${SSH_USER}@${node}" "sudo systemctl start cassandra"\n' +
      '\n' +
      '  log "Waiting for node ${node} to rejoin the cluster..."\n' +
      '  # This is a simple check; a more robust check would loop until status is UN (Up/Normal)\n' +
      '  sleep ${WAIT_TIME}\n' +
      '  ssh "${SSH_USER}@${node}" "nodetool status"\n' +
      '\n' +
      '  log "Node ${node} has been restarted. Waiting ${WAIT_TIME} seconds before proceeding to the next node."\n' +
      '  sleep ${WAIT_TIME}\n' +
      'done\n' +
      '\n' +
      'log "Rolling restart completed for all nodes."\n' +
      ''
    ,
  },
};
    

    