
export const jmx_exporter = `
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
`.trim();
