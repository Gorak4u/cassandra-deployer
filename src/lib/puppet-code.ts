
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
      '      "operatingsystemrelease": [ "7", "8", "9" ]\n' +
      '    },\n' +
      '    {\n' +
      '      "operatingsystem": "CentOS",\n' +
      '      "operatingsystemrelease": [ "7", "8", "9" ]\n' +
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
      '# @summary Manages installation and configuration of Apache Cassandra.\n' +
      '# @param cassandra_version Version of Cassandra to install.\n' +
      '# @param java_version Java major version to install.\n' +
      '# @param cluster_name Name of the Cassandra cluster.\n' +
      '# @param seeds Comma-separated list of seed node IP addresses.\n' +
      '# @param datacenter The datacenter name for this node.\n' +
      '# @param rack The rack name for this node.\n' +
      '# @param max_heap_size JVM maximum heap size.\n' +
      '# @param gc_type The garbage collector type to use.\n' +
      '# @param cassandra_password The password to set for the default cassandra user.\n' +
      '# @param ssl_enabled Whether to enable client-to-node and node-to-node SSL/TLS.\n' +
      '# @param internode_encryption Encryption level for internode communication.\n' +
      'class profile_ggonda_cassandr(\n' +
      "  String \\$cassandra_version         = '4.1.10-1',\n" +
      "  String \\$java_version              = '11',\n" +
      "  String \\$cluster_name              = 'ggonda-cass-cluster',\n" +
      "  String \\$seeds                     = '10.93.16.206,10.93.16.127,10.93.17.191',\n" +
      "  String \\$datacenter                = 'dc1',\n" +
      "  String \\$rack                      = 'rack1',\n" +
      "  String \\$max_heap_size             = '3G',\n" +
      "  String \\$gc_type                   = 'G1GC',\n" +
      "  String \\$cassandra_password        = 'PP#C@ss@ndr@000',\n" +
      "  String \\$data_dir                  = '/var/lib/cassandra/data',\n" +
      "  String \\$commitlog_dir             = '/var/lib/cassandra/commitlog',\n" +
      "  Boolean \\$disable_swap              = false,\n" +
      "  String  \\$replace_address           = '',\n" +
      "  Boolean \\$enable_range_repair       = false,\n" +
      "  String \\$listen_address            = \\$facts['networking']['ip'],\n" +
      "  Boolean \\$ssl_enabled               = true,\n" +
      "  String \\$keystore_path             = '/etc/pki/tls/certs/etc/keystore.jks',\n" +
      "  String \\$keystore_password         = 'ChangeMe',\n" +
      "  String \\$internode_encryption      = 'all',\n" +
      "  String \\$truststore_path           = '/etc/pki/ca-trust/extracted/java/cacerts',\n" +
      "  String \\$truststore_password       = 'changeit',\n" +
      "  String \\$repo_baseurl              = 'https://repocache.nonprod.ppops.net/artifactory/apache-org-cassandra/',\n" +
      "  String \\$repo_gpgkey               = 'https://repocache.nonprod.ppops.net/artifactory/apache-org-cassandra-gpg-keys/KEYS',\n" +
      "  String \\$cassandra_user            = 'cassandra',\n" +
      "  String \\$cassandra_group           = 'cassandra',\n" +
      "  Array[String] \\$package_dependencies = ['jemalloc','python3','numactl'],\n" +
      "  String \\$manage_bin_dir            = '/usr/local/bin',\n" +
      "  String \\$change_password_cql       = '/tmp/change_password.cql',\n" +
      "  String \\$cqlsh_path_env            = '/usr/bin:/usr/local/bin',\n" +
      "  String \\$jamm_target               = '/usr/share/cassandra/lib/jamm-0.3.2.jar',\n" +
      "  String \\$jamm_source               = 'puppet:///modules/ggonda_cassandra/jamm-0.3.2.jar',\n" +
      ') {\n\n' +
      "  # Ensure Cassandra user and group exist\n" +
      "  user { \\$cassandra_user:\n" +
      "    ensure     => 'present',\n" +
      "    system     => true,\n" +
      '  }\n\n' +
      "  group { \\$cassandra_group:\n" +
      "    ensure => 'present',\n" +
      "    system => true,\n" +
      '  }\n\n' +
      '  # YUM Repo for Cassandra\n' +
      "  \\$os_release_major = regsubst(\\$::operatingsystemrelease, '^(\\\\d+).*$', '\\\\1')\n\n" +
      "  yumrepo { 'cassandra':\n" +
      "    descr    => \\\"Apache Cassandra \\${cassandra_version} for EL\\${os_release_major}\\\",\n" +
      "    baseurl  => \\\"\\${repo_baseurl}\\\",\n" +
      '    gpgcheck => 0,\n' +
      '    enabled  => 1,\n' +
      "    gpgkey   => \\\"\\${repo_gpgkey}\\\",\n" +
      '    repo_gpgcheck => 0,\n' +
      '    skip_if_unavailable => 1,\n' +
      '    priority => 99,\n' +
      '    sslverify => 1,\n' +
      '  }\n\n' +
      '  # Install Java\n' +
      "  if \\$java_version == '8' {\n" +
      "    \\$actual_java_package = 'java-1.8.0-openjdk-headless'\n" +
      "  } elsif \\$java_version == '11' {\n" +
      "    \\$actual_java_package = 'java-11-openjdk-headless'\n" +
      "  } elsif \\$java_version == '17' {\n" +
      "    \\$actual_java_package = 'java-17-openjdk-headless'\n" +
      '  } else {\n' +
      "    \\$actual_java_package = \\\"java-\\${java_version}-openjdk-headless\\\" # Fallback\n" +
      '  }\n\n' +
      "  package { \\$actual_java_package:\n" +
      '    ensure  => present,\n' +
      "    before  => Package['cassandra'],\n" +
      "    require => Yumrepo['cassandra'],\n" +
      '  }\n\n' +
      '  # Install dependencies\n' +
      "  package { \\$package_dependencies:\n" +
      "    ensure => 'present',\n" +
      '  }\n\n' +
      '  # Install Cassandra and tools\n' +
      "  package { 'cassandra':\n" +
      "    ensure  => \\$cassandra_version ? {\n" +
      "      undef   => present,  # fallback when not provided\n" +
      "      default => \\$cassandra_version,\n" +
      '    },\n' +
      "    require => Yumrepo['cassandra'],\n" +
      "    before  => Service['cassandra'],\n" +
      '  }\n\n' +
      "  package { 'cassandra-tools':\n" +
      "    ensure  => \\$cassandra_version ? {\n" +
      "      undef   => present,\n" +
      "      default => \\$cassandra_version,\n" +
      '    },\n' +
      "    require => Yumrepo['cassandra'],\n" +
      "    before  => Service['cassandra'],\n" +
      '  }\n\n' +
      '  # Create Cassandra data and commitlog directories\n' +
      "  file { [\\$data_dir, \\$commitlog_dir]:\n" +
      "    ensure  => 'directory',\n" +
      "    owner   => \\$cassandra_user,\n" +
      "    group   => \\$cassandra_group,\n" +
      "    mode    => '0700',\n" +
      "    require => User[\\$cassandra_user],\n" +
      '  }\n\n' +
      "  # Create .cassandra directory for cqlshrc\n" +
      "  file { '/root/.cassandra':\n" +
      "    ensure => 'directory',\n" +
      "    owner  => 'root',\n" +
      "    group  => 'root',\n" +
      "    mode   => '0700',\n" +
      '  }\n\n' +
      "  file { \\$jamm_target:\n" +
      "    ensure  => 'file',\n" +
      "    owner   => 'root',\n" +
      "    group   => 'root',\n" +
      "    mode    => '0644',\n" +
      "    source  => \\$jamm_source,\n" +
      "    require => Package['cassandra'],\n" +
      '  }\n\n' +
      '  # Cassandra configuration files\n' +
      "  file { '/etc/cassandra/conf/cassandra.yaml':\n" +
      "    ensure  => 'file',\n" +
      "    content => template('ggonda_cassandra/cassandra.yaml.erb'),\n" +
      "    owner   => \\$cassandra_user,\n" +
      "    group   => \\$cassandra_group,\n" +
      "    mode    => '0644',\n" +
      "    require => Package['cassandra'],\n" +
      "    notify  => Service['cassandra'],\n" +
      '  }\n\n' +
      "  file { '/etc/cassandra/conf/cassandra-rackdc.properties':\n" +
      "    ensure  => 'file',\n" +
      "    content => template('ggonda_cassandra/cassandra-rackdc.properties.erb'),\n" +
      "    owner   => \\$cassandra_user,\n" +
      "    group   => \\$cassandra_group,\n" +
      "    mode    => '0644',\n" +
      "    require => Package['cassandra'],\n" +
      "    notify  => Service['cassandra'],\n" +
      '  }\n\n' +
      "  file { '/etc/cassandra/conf/jvm-server.options':\n" +
      "    ensure  => 'file',\n" +
      "    content => template('ggonda_cassandra/jvm-options.erb'),\n" +
      "    owner   => \\$cassandra_user,\n" +
      "    group   => \\$cassandra_group,\n" +
      "    mode    => '0644',\n" +
      "    require => Package['cassandra'],\n" +
      "    notify  => Service['cassandra'],\n" +
      '  }\n\n' +
      "  file { '/etc/cassandra/conf/jvm11-server.options':\n" +
      "    ensure  => 'file',\n" +
      "    content => template('ggonda_cassandra/jvm11-server.options.erb'),\n" +
      "    owner   => \\$cassandra_user,\n" +
      "    group   => \\$cassandra_group,\n" +
      "    mode    => '0644',\n" +
      "    require => Package['cassandra'],\n" +
      "    notify  => Service['cassandra'],\n" +
      '  }\n\n' +
      "  file { '/etc/cassandra/conf/jvm8-server.options':\n" +
      "    ensure  => 'file',\n" +
      "    content => template('ggonda_cassandra/jvm8-server.options.erb'),\n" +
      "    owner   => \\$cassandra_user,\n" +
      "    group   => \\$cassandra_group,\n" +
      "    mode    => '0644',\n" +
      "    require => Package['cassandra'],\n" +
      "    notify  => Service['cassandra'],\n" +
      '  }\n\n' +
      "  file { '/root/.cassandra/cqlshrc':\n" +
      "    ensure  => 'file',\n" +
      "    content => template('ggonda_cassandra/cqlshrc.erb'),\n" +
      "    owner   => 'root',\n" +
      "    group   => 'root',\n" +
      "    mode    => '0600',\n" +
      "    require => File['/root/.cassandra'],\n" +
      '  }\n\n' +
      '  # Cassandra service\n' +
      "  service { 'cassandra':\n" +
      "    ensure     => running,\n" +
      "    enable     => true,\n" +
      "    hasstatus  => true,\n" +
      "    hasrestart => true,\n" +
      '    require    => [\n' +
      "      Package['cassandra'],\n" +
      "      File['/etc/cassandra/conf/cassandra.yaml'],\n" +
      "      File['/etc/cassandra/conf/cassandra-rackdc.properties'],\n" +
      "      File['/etc/cassandra/conf/jvm-server.options'],\n" +
      '    ],\n' +
      '  }\n\n' +
      "  file { \\$change_password_cql:\n" +
      "    ensure  => file,\n" +
      "    content => \\\"ALTER USER cassandra WITH PASSWORD '\\${cassandra_password}';\\\\n\\\",\n" +
      "    owner   => 'root',\n" +
      "    group   => 'root',\n" +
      "    mode    => '0600',\n" +
      '  }\n\n' +
      '  # Wait for Cassandra to start up before attempting to change password\n' +
      "  exec { 'change_cassandra_password':\n" +
      "    command     => \\\"cqlsh -u cassandra -p cassandra -f \\${change_password_cql}\\\",\n" +
      "    path        => \\$cqlsh_path_env, # Ensure cqlsh is in path\n" +
      '    tries       => 12, # Try 12 times\n' +
      '    try_sleep   => 10, # Wait 10 seconds between tries (total 2 minutes)\n' +
      "    unless      => \\\"cqlsh -u cassandra -p '\\${cassandra_password}' -e 'SELECT cluster_name FROM system.local;' \\${listen_address} >/dev/null 2>&1\\\",\n" +
      "    require     => [Service['cassandra'], File[\\$change_password_cql]],\n" +
      '  }\n\n' +
      '  # Deploy management scripts\n' +
      "  file { \\$manage_bin_dir:\n" +
      "    ensure => 'directory',\n" +
      "    owner  => 'root',\n" +
      "    group  => 'root',\n" +
      "    mode   => '0755',\n" +
      '  }\n\n' +
      "  [ 'cassandra-upgrade-precheck.sh', 'cluster-health.sh', 'repair-node.sh',\n" +
      "    'cleanup-node.sh', 'take-snapshot.sh', 'drain-node.sh', 'rebuild-node.sh',\n" +
      "    'garbage-collect.sh', 'assassinate-node.sh', 'upgrade-sstables.sh',\n" +
      "    'backup-to-s3.sh', 'prepare-replacement.sh', 'version-check.sh',\n" +
      "    'cassandra_range_repair.py', 'range-repair.sh' ].each |\\$script| {\n" +
      "    file { \\\"\\${manage_bin_dir}/\\${script}\\\":\n" +
      "      ensure  => 'file',\n" +
      "      source  => \\\"puppet:///modules/ggonda_cassandra/\\${script}\\\",\n" +
      "      owner   => 'root',\n" +
      "      group   => 'root',\n" +
      "      mode    => '0755',\n" +
      '    }\n' +
      '  }\n\n' +
      '  # Range Repair Service (Systemd)\n' +
      "  \\$range_repair_ensure = \\\"\\${enable_range_repair}\\\" ? { 'true' => 'running', default => 'stopped' }\n" +
      "  \\$range_repair_enable = \\\"\\${enable_range_repair}\\\" ? { 'true' => true, default => false }\n\n" +
      "  file { '/etc/systemd/system/range-repair.service':\n" +
      "    ensure  => 'file',\n" +
      "    content => template('ggonda_cassandra/range-repair.service.erb'),\n" +
      "    owner   => 'root',\n" +
      "    group   => 'root',\n" +
      "    mode    => '0644',\n" +
      "    notify  => Exec['systemctl_daemon_reload_range_repair'],\n" +
      "    require => File[\\\"\\${manage_bin_dir}/range-repair.sh\\\"],\n" +
      '  }\n\n' +
      "  exec { 'systemctl_daemon_reload_range_repair':\n" +
      "    command     => '/bin/systemctl daemon-reload',\n" +
      "    path        => ['/usr/bin', '/bin'],\n" +
      "    refreshonly => true,\n" +
      "    before      => Service['range-repair'],\n" +
      '  }\n\n' +
      "  service { 'range-repair':\n" +
      "    ensure    => \\$range_repair_ensure,\n" +
      "    enable    => \\$range_repair_enable,\n" +
      "    hasstatus => true,\n" +
      "    hasrestart => true,\n" +
      "    subscribe => File['/etc/systemd/system/range-repair.service'],\n" +
      '  }\n\n' +
      '  # OS Tuning for Cassandra\n' +
      "  if \\\"\\${disable_swap}\\\" == \\\"true\\\" {\n" +
      "    exec { 'swapoff -a':\n" +
      "      command  => '/sbin/swapoff -a',\n" +
      "      unless   => '/sbin/swapon -s | /bin/grep -qE \\\"^/[^ ]+\\\\s+partition\\\\s+0\\\\s+0$\\\"',\n" +
      "      path     => ['/usr/bin', '/usr/sbin', '/bin', '/sbin'],\n" +
      "      before   => File['/etc/sysctl.d/99-cassandra.conf'],\n" +
      '    }\n\n' +
      "    file { '/etc/sysctl.d/99-cassandra.conf':\n" +
      "      ensure  => 'file',\n" +
      "      content => \\\"vm.swappiness = 0\\\\nfs.aio-max-nr = 1048576\\\\n\\\",\n" +
      "      mode    => '0644',\n" +
      "      owner   => 'root',\n" +
      "      group   => 'root',\n" +
      "      notify  => Exec['apply_sysctl_cassandra'],\n" +
      '    }\n\n' +
      "    exec { 'apply_sysctl_cassandra':\n" +
      "      command     => '/sbin/sysctl -p /etc/sysctl.d/99-cassandra.conf',\n" +
      "      path        => ['/usr/bin', '/usr/sbin', '/bin', '/sbin'],\n" +
      "      refreshonly => true,\n" +
      '    }\n\n' +
      "    file { '/etc/security/limits.d/cassandra.conf':\n" +
      "      ensure  => 'file',\n" +
      "      content => \\\"cassandra - memlock unlimited\\\\ncassandra - nofile 100000\\\\ncassandra - nproc 32768\\\\ncassandra - as unlimited\\\\n\\\",\n" +
      "      mode    => '0644',\n" +
      "      owner   => 'root',\n" +
      "      group   => 'root',\n" +
      '    }\n' +
      '  }\n' +
      '}',
  },
  templates: {
    'cassandra.yaml.erb': 
      '# cassandra.yaml\n' +
      '# Generated by Puppet from ggonda_cassandra/cassandra.yaml.erb. DO NOT EDIT.\n' +
      '\n' +
      "cluster_name: '<%= @cluster_name %>'\n" +
      'num_tokens: 256\n' +
      "listen_address: <%= @listen_address %>\n" +
      "rpc_address: <%= @listen_address %>\n" +
      'seed_provider:\n' +
      '  - class_name: org.apache.cassandra.locator.SimpleSeedProvider\n' +
      '    parameters:\n' +
      "      - seeds: \"<%= @seeds %>\"\n" +
      "endpoint_snitch: GossipingPropertyFileSnitch\n" +
      "data_file_directories:\n" +
      "  - <%= @data_dir %>\n" +
      "commitlog_directory: <%= @commitlog_dir %>\n" +
      "saved_caches_directory: /var/lib/cassandra/saved_caches\n" +
      "authenticator: PasswordAuthenticator\n" +
      "authorizer: CassandraAuthorizer\n" +
      '<% if @ssl_enabled == true -%>\n' +
      'server_encryption_options:\n' +
      "  internode_encryption: <%= @internode_encryption %>\n" +
      "  keystore: <%= @keystore_path %>\n" +
      "  keystore_password: <%= @keystore_password %>\n" +
      "  truststore: <%= @truststore_path %>\n" +
      "  truststore_password: <%= @truststore_password %>\n" +
      'client_encryption_options:\n' +
      '  enabled: true\n' +
      "  keystore: <%= @keystore_path %>\n" +
      "  keystore_password: <%= @keystore_password %>\n" +
      '<% end -%>\n' +
      '<% if @replace_address != "" -%>\n' +
      "replace_address_first_boot: <%= @replace_address %>\n" +
      '<% end -%>',
    'cassandra-rackdc.properties.erb': 
      '# cassandra-rackdc.properties\n' +
      '# Generated by Puppet\n' +
      '# Used by GossipingPropertyFileSnitch\n' +
      'dc=<%= @datacenter %>\n' +
      'rack=<%= @rack %>\n',
    'jvm-server.options.erb': 
      '# jvm-server.options\n' +
      '# Generated by Puppet\n' +
      '# This file is for Cassandra 4.x and later.\n' +
      '<% if @java_version.to_i >= 11 -%>\n' +
      '-Xms<%= @max_heap_size %>\n' +
      '-Xmx<%= @max_heap_size %>\n' +
      '<% if @gc_type == "G1GC" -%>\n' +
      '-XX:+UseG1GC\n' +
      '-XX:G1RSetUpdatingPauseTimePercent=5\n' +
      '-XX:MaxGCPauseMillis=500\n' +
      '<% else -%>\n' +
      '-XX:+UseShenandoahGC\n' +
      '<% end -%>\n' +
      '-XX:+HeapDumpOnOutOfMemoryError\n' +
      '-Dcassandra.jmx.local.port=7199\n' +
      '<% else -%>\n' +
      '-Xms4G\n' +
      '-Xmx4G\n' +
      '-XX:+UseConcMarkSweepGC\n' +
      '-XX:+CMSParallelRemarkEnabled\n' +
      '<% end -%>',
    'jvm8-server.options.erb':
      '-Xms4G\n-Xmx4G\n-XX:+UseConcMarkSweepGC\n-XX:+CMSParallelRemarkEnabled\n',
    'jvm11-server.options.erb':
      '-Xms<%= @max_heap_size %>\n-Xmx<%= @max_heap_size %>\n<% if @gc_type == "G1GC" -%>\n-XX:+UseG1GC\n-XX:G1RSetUpdatingPauseTimePercent=5\n-XX:MaxGCPauseMillis=500\n<% else -%>\n-XX:+UseShenandoahGC\n<% end -%>\n',
    'cqlshrc.erb':
      "[authentication]\nusername = cassandra\npassword = <%= @cassandra_password %>",
    'range-repair.service.erb':
      '[Unit]\nDescription=Cassandra Range Repair Service\n\n[Service]\nType=simple\nUser=cassandra\nGroup=cassandra\nExecStart=/usr/local/bin/range-repair.sh\nRestart=on-failure\n\n[Install]\nWantedBy=multi-user.target',
  },
  scripts: {
    'cassandra-upgrade-precheck.sh': '#!/bin/bash\n# Placeholder for cassandra-upgrade-precheck.sh\necho "Cassandra Upgrade Pre-check Script"',
    'cluster-health.sh': '#!/bin/bash\n# Placeholder for cluster-health.sh\necho "Cluster Health Script"',
    'repair-node.sh': '#!/bin/bash\n# Placeholder for repair-node.sh\necho "Repair Node Script"',
    'cleanup-node.sh': '#!/bin/bash\n# Placeholder for cleanup-node.sh\necho "Cleanup Node Script"',
    'take-snapshot.sh': '#!/bin/bash\n# Placeholder for take-snapshot.sh\necho "Take Snapshot Script"',
    'drain-node.sh': '#!/bin/bash\n# Placeholder for drain-node.sh\necho "Drain Node Script"',
    'rebuild-node.sh': '#!/bin/bash\n# Placeholder for rebuild-node.sh\necho "Rebuild Node Script"',
    'garbage-collect.sh': '#!/bin/bash\n# Placeholder for garbage-collect.sh\necho "Garbage Collect Script"',
    'assassinate-node.sh': '#!/bin/bash\n# Placeholder for assassinate-node.sh\necho "Assassinate Node Script"',
    'upgrade-sstables.sh': '#!/bin/bash\n# Placeholder for upgrade-sstables.sh\necho "Upgrade SSTables Script"',
    'backup-to-s3.sh': '#!/bin/bash\n# Placeholder for backup-to-s3.sh\necho "Backup to S3 Script"',
    'prepare-replacement.sh': '#!/bin/bash\n# Placeholder for prepare-replacement.sh\necho "Prepare Replacement Script"',
    'version-check.sh': '#!/bin/bash\n# Placeholder for version-check.sh\necho "Version Check Script"',
    'cassandra_range_repair.py': '#!/usr/bin/env python3\n# Placeholder for cassandra_range_repair.py\nprint("Cassandra Range Repair Python Script")',
    'range-repair.sh': '#!/bin/bash\n# Placeholder for range-repair.sh\necho "Range Repair Script"',
  },
};
    

    
