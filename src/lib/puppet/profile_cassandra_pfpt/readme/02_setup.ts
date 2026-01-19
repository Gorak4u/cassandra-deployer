
export const setup = `
## Setup

This profile is intended to be included by a role class. For example:

\`\`\`puppet
# In your role manifest (e.g., roles/manifests/cassandra.pp)
class role::cassandra {
  include profile_cassandra_pfpt
}
\`\`\`

All configuration for the node should be provided via your Hiera data source (e.g., in your \`common.yaml\` or node-specific YAML files). The backup scripts require the \`jq\` and \`awscli\` packages, which this profile will install by default.
`.trim();
