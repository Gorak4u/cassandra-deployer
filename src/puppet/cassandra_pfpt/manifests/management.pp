# Class: cassandra_pfpt::management
#
# Manages scripts for node and cluster management lifecycle operations.
#
class cassandra_pfpt::management {
  $management_scripts = [
    'assassinate-node.sh',
    'decommission-node.sh',
    'drain-node.sh',
  ]

  $management_scripts.each |String $script| {
    file { "/usr/local/bin/${script}":
      ensure => file,
      owner  => 'root',
      group  => 'root',
      mode   => '0755',
      source => "puppet:///modules/cassandra_pfpt/${script}",
    }
  }
}
