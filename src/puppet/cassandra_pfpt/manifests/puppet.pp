# @summary Manages the Puppet agent itself via cron.
class cassandra_pfpt::puppet {
  if $cassandra_pfpt::puppet_cron_schedule {
    cron { 'puppet-agent-run':
      command => '/opt/puppetlabs/bin/puppet agent -t',
      user    => 'root',
      special => $cassandra_pfpt::puppet_cron_schedule ? {
        /^\@/    => $cassandra_pfpt::puppet_cron_schedule,
        default => undef,
      },
      hour     => $cassandra_pfpt::puppet_cron_schedule ? {
        /^\@/    => undef,
        default => split($cassandra_pfpt::puppet_cron_schedule, ' ')[1],
      },
      minute   => $cassandra_pfpt::puppet_cron_schedule ? {
        /^\@/    => undef,
        default => split($cassandra_pfpt::puppet_cron_schedule, ' ')[0],
      },
    }
  }
}
