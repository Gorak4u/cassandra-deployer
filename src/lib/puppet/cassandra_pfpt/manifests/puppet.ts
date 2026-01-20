
export const puppet = `
# @summary Manages the Puppet agent itself, including scheduled runs.
class cassandra_pfpt::puppet inherits cassandra_pfpt {
  # Stagger the cron job across the hour to avoid all nodes running at once.
  \$cron_minute_1 = fqdn_rand(30)
  \$cron_minute_2 = \$cron_minute_1 + 30

  if \$puppet_cron_schedule and \$puppet_cron_schedule != '' {
    # Split on any whitespace to tolerate multiple spaces/tabs
    \$schedule_parts = split(\$puppet_cron_schedule, ' +')
    if size(\$schedule_parts) != 5 {
      fail("Invalid cron schedule '\\\${puppet_cron_schedule}'. Expected 5 fields, e.g. '*/30 * * * *'.")
    }

    \$raw_minute_field = \$schedule_parts[0]
    # Check if the minute field is a comma-separated list of numbers
    if \$raw_minute_field =~ '^\\\\d+(,\\\\d+)*\$' {
      \$minute = split(\$raw_minute_field, ',')
    } else {
      \$minute = \$raw_minute_field
    }

    \$hour     = \$schedule_parts[1]
    \$monthday = \$schedule_parts[2]
    \$month    = \$schedule_parts[3]
    \$weekday  = \$schedule_parts[4]
  } else {
    # Default staggered schedule: pass an Array for minute
    \$minute   = [\$cron_minute_1, \$cron_minute_2]
    \$hour     = '*'
    \$monthday = '*'
    \$month    = '*'
    \$weekday  = '*'
  }

  cron { 'scheduled_puppet_run':
    ensure   => present,
    command  => '[ ! -f /var/lib/puppet-disabled ] && /opt/puppetlabs/bin/puppet agent -v --onetime',
    user     => 'root',
    minute   => \$minute,
    hour     => \$hour,
    monthday => \$monthday,
    month    => \$month,
    weekday  => \$weekday,
  }
}
`.trim();
