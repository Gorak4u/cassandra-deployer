# Class: cassandra_pfpt::health
#
# Manages health check scripts for Cassandra.
#
class cassandra_pfpt::health {
  $health_scripts = [
    'cluster-health.sh',
    'disk-health-check.sh',
    'cassandra-upgrade-precheck.sh',
  ]

  $health_scripts.each |String $script| {
    file { "/usr/local/bin/${script}":
      ensure => file,
      owner  => 'root',
      group  => 'root',
      mode   => '0755',
      source => "puppet:///modules/cassandra_pfpt/${script}",
    }
  }
}
