# @summary Manages the Puppet agent itself, including scheduled runs (Puppet 3 compatible).
#
# Requirements:
# - puppetlabs-stdlib for fqdn_rand() and split() (common in Puppet 3 estates)
#
# Optionally set $puppet_cron_schedule (e.g., '*/30 * * * *') to override the default.
class cassandra_pfpt::puppet inherits cassandra_pfpt {
  # Stagger the cron job across the hour to avoid all nodes running at once.
  # fqdn_rand(30) -> 0..29, plus 30 -> 30..59
  $cron_minute_1 = fqdn_rand(30)
  $cron_minute_2 = $cron_minute_1 + 30

  # Defaults
  $default_minute   = [$cron_minute_1, $cron_minute_2]
  $default_hour     = '*'
  $default_monthday = '*'
  $default_month    = '*'
  $default_weekday  = '*'

  # If a schedule string is provided, validate it has 5 cron fields and use them.
  if ($puppet_cron_schedule and $puppet_cron_schedule != '') {
    # Split on one or more whitespace characters
    $schedule_parts = split($puppet_cron_schedule, '\s+')

    if size($schedule_parts) != 5 {
      fail("Invalid cron schedule '${puppet_cron_schedule}'. Expected 5 fields, e.g. '*/30 * * * *'.")
    }

    # Fields
    $raw_minute_field = $schedule_parts[0]
    $hour             = $schedule_parts[1]
    $monthday         = $schedule_parts[2]
    $month            = $schedule_parts[3]
    $weekday          = $schedule_parts[4]

    # Puppet 3: avoid converting numeric lists to arrays; pass through as a string.
    # This preserves support for '*/10', '1-5', '0,30', '*/10,5', etc.
    $minute = $raw_minute_field
  } else {
    # Default staggered schedule: pass an Array for minute (supported in Puppet 3)
    $minute   = $default_minute
    $hour     = $default_hour
    $monthday = $default_monthday
    $month    = $default_month
    $weekday  = $default_weekday
  }

  cron { 'scheduled_puppet_run':
    ensure   => present,
    command  => '[ ! -f /var/lib/puppet-disabled ] && /opt/puppetlabs/bin/puppet agent -v --onetime',
    user     => 'root',
    minute   => $minute,
    hour     => $hour,
    monthday => $monthday,
    month    => $month,
    weekday  => $weekday,

    # Optional but often useful to control PATH and suppress mail:
    # environment => [
    #   'PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin',
    #   'MAILTO=""',
    # ],
  }
}
