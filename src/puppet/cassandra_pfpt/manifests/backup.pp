# @summary Manages backup configuration and cron jobs.
class cassandra_pfpt::backup {

  file { '/etc/backup':
    ensure => directory,
    owner  => 'root',
    group  => 'root',
    mode   => '0755',
  }

  $backup_config_hash = {
    's3_bucket_name'                => $cassandra_pfpt::backup_s3_bucket,
    'backup_backend'                => $cassandra_pfpt::backup_backend,
    'cassandra_data_dir'            => $cassandra_pfpt::data_dir,
    'full_backup_log_file'          => $cassandra_pfpt::full_backup_log_file,
    'incremental_backup_log_file'   => $cassandra_pfpt::incremental_backup_log_file,
    'listen_address'                => $cassandra_pfpt::listen_address,
    'clearsnapshot_keep_days'       => $cassandra_pfpt::clearsnapshot_keep_days,
  }

  file { '/etc/backup/config.json':
    ensure  => file,
    content => to_json_pretty($backup_config_hash),
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
    require => File['/etc/backup'],
  }

  if $cassandra_pfpt::manage_full_backups {
    # Translate schedule keywords to cron values
    $full_schedule = $cassandra_pfpt::full_backup_schedule ? {
      'daily'   => { 'minute' => '30', 'hour' => '2' },
      'weekly'  => { 'minute' => '30', 'hour' => '2', 'weekday' => '0' },
      default   => undef,
    }

    if $full_schedule {
      cron { 'cassandra_full_backup':
        command  => $cassandra_pfpt::full_backup_script_path,
        user     => 'root',
        minute   => $full_schedule['minute'],
        hour     => $full_schedule['hour'],
        weekday  => $full_schedule['weekday'],
        require  => File['/etc/backup/config.json'],
      }
    }
  }

  if $cassandra_pfpt::manage_incremental_backups {
    cron { 'cassandra_incremental_backup':
      command  => $cassandra_pfpt::incremental_backup_script_path,
      user     => 'root',
      schedule => $cassandra_pfpt::incremental_backup_schedule,
      require  => File['/etc/backup/config.json'],
    }
  }
}
