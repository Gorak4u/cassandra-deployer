# @summary Manages the JMX Exporter agent for Prometheus monitoring.
class cassandra_pfpt::jmx_exporter {
  file { $cassandra_pfpt::jmx_exporter_jar_target:
    ensure  => file,
    source  => $cassandra_pfpt::jmx_exporter_jar_source,
    owner   => $cassandra_pfpt::user,
    group   => $cassandra_pfpt::group,
    mode    => '0644',
  }
  file { $cassandra_pfpt::jmx_exporter_config_target:
    ensure  => file,
    content => template('cassandra_pfpt/jmx_exporter_config.yaml.erb'),
    owner   => $cassandra_pfpt::user,
    group   => $cassandra_pfpt::group,
    mode    => '0644',
    notify  => Class['cassandra_pfpt::service'],
  }
}
