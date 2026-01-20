# @summary Manages backup scripts, configuration, and cron jobs.
class cassandra_pfpt::backup {

  # Backup configuration file used by the shell scripts
  file { '/etc/backup': ensure => directory }
  file { '/etc/backup/config.json':
    ensure  => file,
    owner   => 'root',
    group   => 'root',
    mode    => '0600',
    content => template('cassandra_pfpt/backup-config.json.erb'),
    require => File['/etc/backup'],
  }

  if $cassandra_pfpt::manage_full_backups {
    cron { 'cassandra_full_backup':
      command  => $cassandra_pfpt::full_backup_script_path,
      user     => 'root',
      hour     => $cassandra_pfpt::full_backup_schedule ? {
        'daily'   => '2',
        default   => '2', # Default to 2 AM daily
      },
      minute   => '0',
      weekday  => $cassandra_pfpt::full_backup_schedule ? {
        'weekly'  => '0', # Sunday
        default   => undef,
      },
      require => [File[$cassandra_pfpt::full_backup_script_path], File['/etc/backup/config.json']],
    }
  }

  if $cassandra_pfpt::manage_incremental_backups {
    cron { 'cassandra_incremental_backup':
      command  => $cassandra_pfpt::incremental_backup_script_path,
      user     => 'root',
      # Handle special cron schedules like @hourly
      special  => $cassandra_pfpt::incremental_backup_schedule ? {
        /^\@/    => $cassandra_pfpt::incremental_backup_schedule,
        default => undef,
      },
      # Handle standard cron schedules
      hour     => $cassandra_pfpt::incremental_backup_schedule ? {
        /^\@/    => undef,
        default => split($cassandra_pfpt::incremental_backup_schedule, ' ')[1],
      },
      minute   => $cassandra_pfpt::incremental_backup_schedule ? {
        /^\@/    => undef,
        default => split($cassandra_pfpt::incremental_backup_schedule, ' ')[0],
      },
      require => [File[$cassandra_pfpt::incremental_backup_script_path], File['/etc/backup/config.json']],
    }
  }
}
