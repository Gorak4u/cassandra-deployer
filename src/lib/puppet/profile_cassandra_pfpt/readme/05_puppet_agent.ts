
export const puppet_agent = `
## Puppet Agent Management

The base \`cassandra_pfpt\` component module includes logic to manage the Puppet agent itself by ensuring a scheduled run is in place via cron. This profile exposes the configuration for that feature.

*   **Scheduled Runs:** By default, the Puppet agent will run twice per hour at a staggered minute (e.g., at 15 and 45 minutes past the hour) to distribute the load on the Puppet primary server.
*   **Maintenance Window:** The cron job will **not** run if a file exists at \`/var/lib/puppet-disabled\`. Creating this file is the standard way to temporarily disable Puppet runs on a node during maintenance.
*   **Configuration:** You can override the default schedule by setting the \`profile_cassandra_pfpt::puppet_cron_schedule\` key in Hiera to a standard 5-field cron string.
`.trim();
