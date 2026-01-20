# Class: cassandra_pfpt::maintenance
#
# Manages scripts for routine Cassandra maintenance tasks.
#
class cassandra_pfpt::maintenance {
  $maintenance_scripts = [
    'cassandra_range_repair.py',
    'cleanup-node.sh',
    'compaction-manager.sh',
    'garbage-collect.sh',
  ]

  $maintenance_scripts.each |String $script| {
    file { "/usr/local/bin/${script}":
      ensure => file,
      owner  => 'root',
      group  => 'root',
      mode   => '0755',
      source => "puppet:///modules/cassandra_pfpt/${script}",
    }
  }
}
