
export const usage = `
## Usage Examples

### Basic Single-Node Cluster

A minimal Hiera configuration for a single-node cluster that seeds from itself.

\`\`\`yaml
# common.yaml
profile_cassandra_pfpt::cluster_name: 'MyTestCluster'
profile_cassandra_pfpt::cassandra_password: 'a-very-secure-password'
\`\`\`

### Multi-Node Cluster

For a multi-node cluster, you define the seed nodes for the cluster to use for bootstrapping.

\`\`\`yaml
# common.yaml
profile_cassandra_pfpt::seeds_list:
  - '10.0.1.10'
  - '10.0.1.11'
  - '10.0.1.12'
\`\`\`

### Managing Cassandra Roles

You can declaratively manage Cassandra user roles.

\`\`\`yaml
profile_cassandra_pfpt::cassandra_roles:
  'readonly_user':
    password: 'SafePassword123'
    is_superuser: false
    can_login: true
  'app_admin':
    password: 'AnotherSafePassword456'
    is_superuser: true
    can_login: true
\`\`\`
`.trim();
