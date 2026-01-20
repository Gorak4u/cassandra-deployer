# @summary Manages replication factor of system keyspaces.
class cassandra_pfpt::system_keyspaces {

  if !empty($cassandra_pfpt::system_keyspaces_replication) {
    $cql_script_path = '/tmp/update_system_keyspaces.cql'
    $cql_commands = $cassandra_pfpt::system_keyspaces_replication.map |$keyspace, $replication_map| {
      $replication_str = join($replication_map.map |$k, $v| { "'${k}': '${v}'" }, ', ')
      "ALTER KEYSPACE ${keyspace} WITH replication = { ${replication_str} };"
    }
    $cql_script_content = join($cql_commands, "\n")

    file { $cql_script_path:
      ensure  => file,
      content => $cql_script_content,
      owner   => 'root',
      group   => 'root',
      mode    => '0644',
    }

    exec { 'apply_system_keyspace_replication_changes':
      command   => "${cassandra_pfpt::cqlsh_path_env} -f ${cql_script_path}",
      path      => ['/bin', '/usr/bin'],
      user      => $cassandra_pfpt::user,
      onlyif    => 'nodetool status | grep -q "UN"', # Only run if node is up
      subscribe => File[$cql_script_path],
      refreshonly => true, # This exec only runs when the CQL script changes
      require   => [Class['cassandra_pfpt::service'], File[$cql_script_path]],
    }
  }
}
