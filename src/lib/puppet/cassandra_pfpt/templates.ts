
export const templates = {
      'cassandra.yaml.erb': `
cluster_name: '<%= @cluster_name %>'
<% if @num_tokens -%>
num_tokens: <%= @num_tokens %>
<% end -%>
<% if @hints_directory -%>
hints_directory: <%= @hints_directory %>
<% end -%>
<% if @authenticator -%>
authenticator: <%= @authenticator %>
<% end -%>
<% if @authorizer -%>
authorizer: <%= @authorizer %>
<% end -%>
<% if @role_manager -%>
role_manager: <%= @role_manager %>
<% end -%>
<% if @endpoint_snitch -%>
endpoint_snitch: <%= @endpoint_snitch %>
<% end -%>
data_file_directories:
    - <%= @data_dir %>
commitlog_directory: <%= @commitlog_dir %>
<% if @cdc_raw_directory -%>
cdc_raw_directory: <%= @cdc_raw_directory %>
<% end -%>

seed_provider:
    - class_name: org.apache.cassandra.locator.SimpleSeedProvider
      parameters:
          - seeds: "<%= @seeds %>"

<% if @listen_address -%>
listen_address: '<%= @listen_address %>'
<% end -%>
<% if @listen_interface -%>
listen_interface: '<%= @listen_interface %>'
<% end -%>
<% if @broadcast_address -%>
broadcast_address: '<%= @broadcast_address %>'
<% end -%>
<% if @rpc_interface -%>
rpc_interface: '<%= @rpc_interface %>'
<% end -%>
<% if @broadcast_rpc_address -%>
broadcast_rpc_address: '<%= @broadcast_rpc_address %>'
<% end -%>
<% if @native_transport_port -%>
native_transport_port: <%= @native_transport_port %>
<% end -%>
<% if @storage_port -%>
storage_port: <%= @storage_port %>
<% end -%>
<% if @ssl_storage_port -%>
ssl_storage_port: <%= @ssl_storage_port %>
<% end -%>

<% if @start_native_transport -%>
start_native_transport: <%= @start_native_transport %>
<% end -%>
<% if @start_rpc -%>
start_rpc: <%= @start_rpc %>
<% end -%>
<% if @rpc_port -%>
rpc_port: <%= @rpc_port %>
<% end -%>

<% if @dynamic_snitch -%>
dynamic_snitch: <%= @dynamic_snitch %>
<% end -%>
<% if @phi_convict_threshold -%>
phi_convict_threshold: <%= @phi_convict_threshold %>
<% end -%>

<% if @concurrent_reads -%>
concurrent_reads: <%= @concurrent_reads %>
<% end -%>
<% if @concurrent_writes -%>
concurrent_writes: <%= @concurrent_writes %>
<% end -%>
<% if @concurrent_counter_writes -%>
concurrent_counter_writes: <%= @concurrent_counter_writes %>
<% end -%>
<% if @memtable_allocation_type -%>
memtable_allocation_type: <%= @memtable_allocation_type %>
<% end -%>
<% if @disk_optimization_strategy -%>
disk_optimization_strategy: <%= @disk_optimization_strategy %>
<% end -%>

<% if @key_cache_size_in_mb -%>
key_cache_size_in_mb: <%= @key_cache_size_in_mb %>
<% end -%>
<% if @counter_cache_size_in_mb -%>
counter_cache_size_in_mb: <%= @counter_cache_size_in_mb %>
<% end -%>
<% if @file_cache_size_in_mb -%>
file_cache_size_in_mb: <%= @file_cache_size_in_mb %>
<% end -%>
<% if @index_summary_capacity_in_mb -%>
index_summary_capacity_in_mb: <%= @index_summary_capacity_in_mb %>
<% end -%>

<% if @commitlog_sync -%>
commitlog_sync: <%= @commitlog_sync %>
<% end -%>
<% if @commitlog_sync_period_in_ms -%>
commitlog_sync_period_in_ms: <%= @commitlog_sync_period_in_ms %>
<% end -%>
<% if @commit_failure_policy -%>
commit_failure_policy: <%= @commit_failure_policy %>
<% end -%>

<% if @request_timeout_in_ms -%>
request_timeout_in_ms: <%= @request_timeout_in_ms %>
<% end -%>
<% if @read_request_timeout_in_ms -%>
read_request_timeout_in_ms: <%= @read_request_timeout_in_ms %>
<% end -%>
<% if @range_request_timeout_in_ms -%>
range_request_timeout_in_ms: <%= @range_request_timeout_in_ms %>
<% end -%>
<% if @write_request_timeout_in_ms -%>
write_request_timeout_in_ms: <%= @write_request_timeout_in_ms %>
<% end -%>
<% if @truncate_request_timeout_in_ms -%>
truncate_request_timeout_in_ms: <%= @truncate_request_timeout_in_ms %>
<% end -%>

<% if @incremental_backups -%>
incremental_backups: <%= @incremental_backups %>
<% end -%>
<% if @auto_snapshot -%>
auto_snapshot: <%= @auto_snapshot %>
<% end -%>

<% if @tombstone_warn_threshold -%>
tombstone_warn_threshold: <%= @tombstone_warn_threshold %>
<% end -%>
<% if @tombstone_failure_threshold -%>
tombstone_failure_threshold: <%= @tombstone_failure_threshold %>
<% end -%>
<% if @compaction_throughput_mb_per_sec -%>
compaction_throughput_mb_per_sec: <%= @compaction_throughput_mb_per_sec %>
<% end -%>
<% if @concurrent_compactors -%>
concurrent_compactors: <%= @concurrent_compactors %>
<% end -%>
<% if @enable_transient_replication -%>
enable_transient_replication: <%= @enable_transient_replication %>
<% end -%>

<% if @ssl_enabled -%>
server_encryption_options:
  internode_encryption: <%= @internode_encryption %>
  keystore: <%= @keystore_path %>
  keystore_password: <%= @keystore_password %>
  require_client_auth: <%= @internode_require_client_auth %>
  <% if @truststore_path && @truststore_password -%>
  truststore: <%= @truststore_path %>
  truststore_password: <%= @truststore_password %>
  <% end -%>
  <% if @tls_protocol -%>
  protocol: <%= @tls_protocol %>
  <% end -%>
  <% if @tls_algorithm -%>
  algorithm: <%= @tls_algorithm %>
  <% end -%>
  <% if @store_type -%>
  store_type: <%= @store_type %>
  <% end -%>

client_encryption_options:
  enabled: true
  optional: <%= @client_optional %>
  keystore: <%= @client_keystore_path %>
  keystore_password: <%= @keystore_password %>
  require_client_auth: <%= @client_require_client_auth %>
  <% if @client_truststore_path && @client_truststore_password -%>
  truststore: <%= @client_truststore_path %>
  truststore_password: <%= @client_truststore_password %>
  <% end -%>
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

# JMX Settings
-Dcassandra.jmx.local.port=7199
-Djava.net.preferIPv4Stack=true
<% if @manage_jmx_security %>
-Dcom.sun.management.jmxremote.port=7199
-Dcom.sun.management.jmxremote.rmi.port=7199
-Dcom.sun.management.jmxremote.ssl=false
-Dcom.sun.management.jmxremote.authenticate=true
-Dcom.sun.management.jmxremote.password.file=<%= @jmx_password_file_path %>
-Dcom.sun.management.jmxremote.access.file=<%= @jmx_access_file_path %>
<% else %>
-Dcom.sun.management.jmxremote.port=7199
-Dcom.sun.management.jmxremote.rmi.port=7199
-Dcom.sun.management.jmxremote.ssl=false
-Dcom.sun.management.jmxremote.authenticate=false
<% end %>

# Other common options
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
certfile =  <%~ "#{@target_dir}/etc/keystore.pem" %>
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
ExecStart=<%= @manage_bin_dir %>/range-repair.sh
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
      'cassandra.service.d.erb': `
# /etc/systemd/system/cassandra.service.d/override.conf
# Generated by Puppet

[Service]
TimeoutStartSec=<%= @service_timeout_start_sec %>
`.trim(),
    'coralogix-agent.conf.erb': `
# Coralogix agent configuration generated by Puppet
private_key: <%= @coralogix_api_key %>
region: <%= @coralogix_region %>
<% if @coralogix_logs_enabled %>
logs:
  - name: "Cassandra System Logs"
    file: "/var/log/cassandra/system.log"
<% end %>
<% if @coralogix_metrics_enabled %>
metrics:
  - name: "Cassandra JMX Metrics"
    type: "jmx"
    endpoint: "service:jmx:rmi:///jndi/rmi://localhost:7199/jmxrmi"
    # Add specific JMX metrics to collect here
    # Example:
    # select:
    #   - "org.apache.cassandra.metrics:type=ClientRequest,scope=Read,name=Latency"
    #   - "org.apache.cassandra.metrics:type=Storage,name=Load"
<% end %>
`.trim(),
    };

