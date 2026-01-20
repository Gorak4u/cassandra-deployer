# Class: cassandra_pfpt::service
#
# This class manages the Cassandra service.
#
class cassandra_pfpt::service {
  service { 'cassandra':
    ensure     => running,
    enable     => true,
    hasstatus  => true,
    hasrestart => true,
    subscribe  => Class['cassandra_pfpt::config'],
  }
}
