#
# @summary This is the main component module for installing and configuring Cassandra.
#
# @param cluster_name The name of the Cassandra cluster.
# @param seeds An array of seed node IP addresses.
# @param backup_config_content A JSON string containing the backup configuration.
#
class cassandra_pfpt (
  String            $cluster_name,
  Array[String]     $seeds,
  Sensitive[String] $backup_config_content,
) {

  # This is a placeholder for all the resources this module would manage,
  # such as packages, configuration files (cassandra.yaml), and the service.
  # For this specific task, we are focusing on the backup configuration.

  # Manages the directory where backup configurations are stored.
  file { '/etc/backup':
    ensure => directory,
    owner  => 'root',
    group  => 'root',
    mode   => '0755',
  }

  # Manages the /etc/backup/config.json file.
  # It receives its content directly from the profile, ensuring data flows one way.
  file { '/etc/backup/config.json':
    ensure  => file,
    owner   => 'root',
    group   => 'root',
    mode    => '0600', # Secure permissions, only root can read.
    content => $backup_config_content,
    require => File['/etc/backup'],
  }

  # Example of how other resources would be declared:
  # package { 'cassandra': ensure => installed }
  # service { 'cassandra': ensure => running, enable => true }
}
