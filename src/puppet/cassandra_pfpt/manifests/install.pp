# Class: cassandra_pfpt::install
#
# This class manages the installation of Cassandra and its dependencies.
#
class cassandra_pfpt::install {
  package { 'cassandra':
    ensure => $cassandra_pfpt::cassandra_version,
  }

  package { ['python3', 'jq', 'nc']:
    ensure => 'present',
  }
}
