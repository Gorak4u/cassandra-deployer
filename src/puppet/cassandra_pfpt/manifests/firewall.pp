# @summary Manages firewall rules for Cassandra.
class cassandra_pfpt::firewall {
  # This is a basic example using firewalld.
  # For a production system, you might use a more specific firewall module.
  $ports_to_open = [
    $cassandra_pfpt::storage_port,              # Inter-node communication
    $cassandra_pfpt::ssl_storage_port,          # Inter-node SSL communication
    7199,                                       # JMX
    $cassandra_pfpt::rpc_port,                  # Thrift
    $cassandra_pfpt::native_transport_port,     # CQL
  ]

  $ports_to_open.each |Integer $port| {
    exec { "firewalld-open-port-${port}":
      command => "/usr/bin/firewall-cmd --permanent --add-port=${port}/tcp && /usr/bin/firewall-cmd --reload",
      unless  => "/usr/bin/firewall-cmd --list-ports | /bin/grep -qw ${port}/tcp",
      path    => ['/bin/', '/sbin/', '/usr/bin/', '/usr/sbin/'],
    }
  }
}
