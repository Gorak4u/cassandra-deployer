# @summary Manages the Cassandra service state.
class cassandra_pfpt::service inherits cassandra_pfpt {
  service { 'cassandra':
    ensure     => 'running',
    enable     => true,
    hasstatus  => true,
    hasrestart => true,
    # This class subscribes to config changes, so it will be notified
    # to restart when configs are updated.
  }
}
