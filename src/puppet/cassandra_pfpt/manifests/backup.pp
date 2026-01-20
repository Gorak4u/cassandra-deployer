# @summary Manages backup configuration, scripts, and scheduling.
class cassandra_pfpt::backup(
  String $s3_bucket_name,
  String $cassandra_data_dir,
  String $commitlog_dir,
  String $saved_caches_dir,
  String $full_backup_log_file,
  String $incremental_backup_log_file,
  String $listen_address,
  Array[String] $seeds_list,
  Sensitive[String] $encryption_key,
  Boolean $manage_full_backups,
  String $full_backup_schedule,
  String $full_backup_script_path,
  Boolean $manage_incremental_backups,
  Variant[String, Array[String]] $incremental_backup_schedule,
  String $incremental_backup_script_path,
  String $backup_backend,
  Integer $clearsnapshot_keep_days,
) {
  # This hash will be converted to the JSON config file
  $config_hash = {
    s3_bucket_name              => $s3_bucket_name,
    backup_backend              => $backup_backend,
    cassandra_data_dir          => $cassandra_data_dir,
    commitlog_dir               => $commitlog_dir,
    saved_caches_dir            => $saved_caches_dir,
    full_backup_log_file        => $full_backup_log_file,
    incremental_backup_log_file => $incremental_backup_log_file,
    listen_address              => $listen_address,
    seeds_list                  => $seeds_list,
    clearsnapshot_keep_days     => $clearsnapshot_keep_days,
    encryption_key              => $encryption_key.unwrap,
  }

  file { '/etc/backup':
    ensure => directory,
    owner  => 'root',
    group  => 'root',
    mode   => '0755',
  }

  file { '/etc/backup/config.json':
    ensure  => file,
    owner   => 'root',
    group   => 'root',
    mode    => '0600', # Restrict access to root
    content => to_json_pretty($config_hash),
    require => File['/etc/backup'],
  }

  if $manage_full_backups {
    systemd::timer { 'cassandra-full-backup':
      ensure             => 'present',
      on_calendar        => $full_backup_schedule,
      persistent         => true,
      service_unit       => 'cassandra-full-backup',
      timer_unit_content => template('cassandra_pfpt/systemd/timer.erb'),
    }

    file { '/etc/systemd/system/cassandra-full-backup.service':
      ensure  => file,
      owner   => 'root',
      group   => 'root',
      mode    => '0644',
      content => template('cassandra_pfpt/systemd/full_backup_service.erb'),
      notify  => Exec['systemd-reload'],
    }
  }

  if $manage_incremental_backups {
    systemd::timer { 'cassandra-incremental-backup':
      ensure             => 'present',
      on_calendar        => $incremental_backup_schedule,
      persistent         => true,
      service_unit       => 'cassandra-incremental-backup',
      timer_unit_content => template('cassandra_pfpt/systemd/timer.erb'),
    }

    file { '/etc/systemd/system/cassandra-incremental-backup.service':
      ensure  => file,
      owner   => 'root',
      group   => 'root',
      mode    => '0644',
      content => template('cassandra_pfpt/systemd/incremental_backup_service.erb'),
      notify  => Exec['systemd-reload'],
    }
  }

  exec { 'systemd-reload':
    command     => '/bin/systemctl daemon-reload',
    refreshonly => true,
  }
}
