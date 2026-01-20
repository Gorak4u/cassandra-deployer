# @summary Manages the Puppet agent's own execution schedule.
class cassandra_pfpt::puppet {
  if $cassandra_pfpt::puppet_cron_schedule {
    cron { 'puppet-agent-run':
      command  => '/opt/puppetlabs/bin/puppet agent -t',
      user     => 'root',
      schedule => $cassandra_pfpt::puppet_cron_schedule,
    }
  }
}
