export const metadata = `
{
  "name": "profile_cassandra_pfpt",
  "version": "1.0.0",
  "author": "Puppet",
  "summary": "Puppet profile for managing Cassandra.",
  "license": "Apache-2.0",
  "source": "",
  "project_page": "",
  "issues_url": "",
  "dependencies": [
    { "name": "cassandra_pfpt", "version_requirement": ">= 1.0.0" }
  ],
  "operatingsystem_support": [
    { "operatingsystem": "RedHat", "operatingsystemrelease": [ "7", "8", "9" ] },
    { "operatingsystem": "CentOS", "operatingsystemrelease": [ "7", "8", "9" ] }
  ],
  "requirements": [
    { "name": "puppet", "version_requirement": ">= 6.0.0 < 8.0.0" }
  ]
}
      `.trim();
