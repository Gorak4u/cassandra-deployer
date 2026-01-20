
export const puppet = `
# @summary Manages the Puppet agent itself, including scheduled runs.
class cassandra_pfpt::puppet inherits cassandra_pfpt {
  # Stagger the cron job across the hour to avoid all nodes running at once.
  $cron_minute_1 = fqdn_rand(30)
  $cron_minute_2 = $cron_minute_1 + 30

  # Check if a custom schedule is provided via Hiera.
  if $\\{puppet_cron_schedule} {
    # If a custom schedule is defined, parse it.
    $schedule_parts = split($\\{puppet_cron_schedule}, ' ')
    $minute         = $schedule_parts[0]
    $hour           = $schedule_parts[1]
    $monthday       = $schedule_parts[2]
    $month          = $schedule_parts[3]
    $weekday        = $schedule_parts[4]
  } else {
    # If no custom schedule, use the default staggered schedule.
    # The minute parameter accepts an array of values.
    $minute   = [$\\
{cron_minute_1}, $\\{cron_minute_2}]
    $hour     = '*'
    $monthday = '*'
    $month    = '*'
    $weekday  = '*'
  }

  cron { 'scheduled_puppet_run':
    command  => '[ ! -f /var/lib/puppet-disabled ] && /opt/puppetlabs/bin/puppet agent -v --onetime',
    user     => 'root',
    minute   => $minute,
    hour     => $hour,
    monthday => $monthday,
    month    => $month,
    weekday  => $weekday,
  }
}
`.trim();
