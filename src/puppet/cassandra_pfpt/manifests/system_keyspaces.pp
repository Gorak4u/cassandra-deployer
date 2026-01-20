# @summary Optionally alters the replication factor of system keyspaces.
class cassandra_pfpt::system_keyspaces {
  # This is critical for multi-datacenter clusters.
  if !empty($cassandra_pfpt::system_keyspaces_replication) {
    # This needs to run after the service is up and the password has been set.
    $cql_command_auth = "ALTER KEYSPACE system_auth WITH REPLICATION = ${cassandra_pfpt::system_keyspaces_replication}"
    exec { 'alter-system-auth-replication':
      command   => "cqlsh -u cassandra -p '${cassandra_pfpt::cassandra_password}' -e \"${cql_command_auth}\"",
      path      => ['/bin', '/usr/bin'],
      unless    => "cqlsh -u cassandra -p '${cassandra_pfpt::cassandra_password}' -e 'DESCRIBE KEYSPACE system_auth' | grep \"'class': 'NetworkTopologyStrategy'\" ",
      require   => Exec['set-initial-cassandra-password'],
      tries     => 3,
      try_sleep => 10,
    }

    $cql_command_traces = "ALTER KEYSPACE system_traces WITH REPLICATION = ${cassandra_pfpt::system_keyspaces_replication}"
    exec { 'alter-system-traces-replication':
      command   => "cqlsh -u cassandra -p '${cassandra_pfpt::cassandra_password}' -e \"${cql_command_traces}\"",
      path      => ['/bin', '/usr/bin'],
      unless    => "cqlsh -u cassandra -p '${cassandra_pfpt::cassandra_password}' -e 'DESCRIBE KEYSPACE system_traces' | grep \"'class': 'NetworkTopologyStrategy'\" ",
      require   => Exec['set-initial-cassandra-password'],
      tries     => 3,
      try_sleep => 10,
    }
  }
}
