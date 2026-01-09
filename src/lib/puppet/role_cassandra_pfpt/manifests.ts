export const manifests = {
      'init.pp': `
# @summary Role class for a Cassandra node.
# This class defines the server's role by including the necessary profiles.
class role_cassandra_pfpt {
  # A Cassandra server is defined by the Cassandra profile.
  include profile_cassandra_pfpt
}
        `.trim(),
    };
