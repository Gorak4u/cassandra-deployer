# @summary Manages the Prometheus JMX Exporter agent.
class cassandra_pfpt::jmx_exporter {
  if $cassandra_pfpt::manage_jmx_exporter {
    # Download the JMX exporter JAR
    archive { "/tmp/jmx_prometheus_javaagent-${cassandra_pfpt::jmx_exporter_version}.jar":
      ensure        => present,
      extract       => false,
      source        => $cassandra_pfpt::jmx_exporter_jar_source,
      cleanup       => true,
      creates       => $cassandra_pfpt::jmx_exporter_jar_target,
      before        => File[$cassandra_pfpt::jmx_exporter_jar_target],
    }
    -> file { $cassandra_pfpt::jmx_exporter_jar_target:
      ensure => file,
      owner  => 'root',
      group  => 'root',
      mode   => '0644',
    }

    # Deploy the JMX exporter configuration
    file { $cassandra_pfpt::jmx_exporter_config_target:
      ensure => file,
      owner  => $cassandra_pfpt::user,
      group  => $cassandra_pfpt::group,
      mode   => '0644',
      source => $cassandra_pfpt::jmx_exporter_config_source,
    }

    # Add the javaagent to JVM options
    $jmx_agent_line = "-javaagent:${cassandra_pfpt::jmx_exporter_jar_target}=${cassandra_pfpt::jmx_exporter_port}:${cassandra_pfpt::jmx_exporter_config_target}"
    
    file_line { 'add_jmx_exporter_to_jvm_options':
      path    => '/etc/cassandra/conf/jvm-server.options',
      line    => $jmx_agent_line,
      match   => "^-javaagent:${cassandra_pfpt::jmx_exporter_jar_target}=",
      require => [
        File[$cassandra_pfpt::jmx_exporter_jar_target],
        File[$cassandra_pfpt::jmx_exporter_config_target],
      ],
      notify  => Service['cassandra'],
    }
  }
}
