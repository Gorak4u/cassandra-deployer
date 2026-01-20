
export const puppet = `
# @summary Manages the Puppet agent itself, including scheduled runs.
class cassandra_pfpt::puppet inherits cassandra_pfpt {
  # Stagger the cron job across the hour to avoid all nodes running at once.
  $cron_minute_1 = fqdn_rand(30)
  $cron_minute_2 = $cron_minute_1 + 30
  
  # Default schedule: runs twice an hour, staggered.
  $default_schedule = "$\\{cron_minute_1},$\\{cron_minute_2} * * * *"
  
  # Use the schedule from the parameter if provided, otherwise use the staggered default.
  $final_schedule = pick($\\
{puppet_cron_schedule}, $default_schedule)

  cron { 'scheduled_puppet_run':
    command  => '[ ! -f /var/lib/puppet-disabled ] && /opt/puppetlabs/bin/puppet agent -v --onetime',
    user     => 'root',
    minute   => split($final_schedule, ' ')[0],
    hour     => split($final_schedule, ' ')[1],
    monthday => split($final_schedule, ' ')[2],
    month    => split($final_schedule, ' ')[3],
    weekday  => split($final_schedule, ' ')[4],
  }
}
`.trim();
