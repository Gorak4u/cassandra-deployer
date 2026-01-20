# @summary Manages the Cassandra service.
class cassandra_pfpt::service {
  service { 'cassandra':
    ensure    => 'running',
    enable    => true,
    subscribe => [
      File['/etc/cassandra/conf/cassandra.yaml'],
      File['/etc/cassandra/conf/jvm-server.options'],
      File['/etc/cassandra/conf/cassandra-rackdc.properties'],
    ],
  }
}
