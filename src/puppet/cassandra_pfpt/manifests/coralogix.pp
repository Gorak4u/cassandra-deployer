# @summary Manages Coralogix agent installation and configuration.
class cassandra_pfpt::coralogix {
  if $cassandra_pfpt::manage_coralogix_agent {
    # This is a placeholder for a real Coralogix agent management module.
    # In a real scenario, you would use the Coralogix Puppet module.
    $install_script_url = "https://raw.githubusercontent.com/coralogix/coralogix-agent/main/install.sh"
    $install_command = "bash <(curl -sL ${install_script_url}) --key ${cassandra_pfpt::coralogix_api_key} --region ${cassandra_pfpt::coralogix_region}"

    exec { 'install-coralogix-agent':
      command => $install_command,
      path    => ['/bin', '/usr/bin'],
      creates => '/opt/coralogix/logs/coralogix.log', # Simple check to see if it's installed
      logoutput => true,
    }
  }
}
