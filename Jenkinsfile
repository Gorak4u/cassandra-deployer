// Define the path where your scripts are located on the Jenkins agent.
// You must ensure the 'scripts' directory from your project is copied here.
def scriptDir = '/opt/cassandra-tools/scripts'

pipeline {
    agent { label 'cassandra-ops' } // Use your dedicated Jenkins agent label

    parameters {
        choice(
            name: 'OPERATION',
            choices: [
                'ROLLING_RESTART',
                'ROLLING_REBOOT',
                'ROLLING_PUPPET_RUN',
                'JOIN_DCS',
                'SPLIT_DCS',
                'RENAME_CLUSTER'
            ],
            description: 'The high-level operation to perform.'
        )
        string(name: 'QV_QUERY_PRIMARY', defaultValue: '', description: 'Primary qv query (e.g., for restarts, renames, or the first DC in a join/split).')
        string(name: 'QV_QUERY_SECONDARY', defaultValue: '', description: 'Secondary qv query (e.g., for the second DC in a join/split).')
        string(name: 'DC_NAME_PRIMARY', defaultValue: '', description: 'The Cassandra name for the primary datacenter.')
        string(name: 'DC_NAME_SECONDARY', defaultValue: '', description: 'The Cassandra name for the secondary datacenter.')
        string(name: 'OLD_CLUSTER_NAME', defaultValue: '', description: 'The old cluster name (for rename operations).')
        string(name: 'NEW_CLUSTER_NAME', defaultValue: '', description: 'The new cluster name (for rename operations).')
    }

    stages {
        stage('Setup') {
            steps {
                // Ensure all management scripts at the specified path are executable.
                sh "chmod +x ${scriptDir}/*.sh"
            }
        }

        stage('Execute Operation') {
            steps {
                sshagent(credentials: ['your-jenkins-ssh-key-id']) {
                    script {
                        def operation = params.OPERATION
                        
                        echo "Executing operation: ${operation}"

                        if (operation == 'ROLLING_RESTART') {
                            sh "${scriptDir}/rolling_restart.sh --qv-query \"${params.QV_QUERY_PRIMARY}\""
                        } else if (operation == 'ROLLING_REBOOT') {
                            sh "${scriptDir}/rolling_reboot.sh --qv-query \"${params.QV_QUERY_PRIMARY}\""
                        } else if (operation == 'ROLLING_PUPPET_RUN') {
                            sh "${scriptDir}/rolling_puppet_run.sh --qv-query \"${params.QV_QUERY_PRIMARY}\""
                        } else if (operation == 'JOIN_DCS') {
                            sh "${scriptDir}/join-cassandra-dcs.sh --old-dc-query \"${params.QV_QUERY_PRIMARY}\" --new-dc-query \"${params.QV_QUERY_SECONDARY}\" --old-dc-name \"${params.DC_NAME_PRIMARY}\" --new-dc-name \"${params.DC_NAME_SECONDARY}\""
                        } else if (operation == 'SPLIT_DCS') {
                            sh "${scriptDir}/split-cassandra-dcs.sh --dc1-query \"${params.QV_QUERY_PRIMARY}\" --dc2-query \"${params.QV_QUERY_SECONDARY}\" --dc1-name \"${params.DC_NAME_PRIMARY}\" --dc2-name \"${params.DC_NAME_SECONDARY}\""
                        } else if (operation == 'RENAME_CLUSTER') {
                            sh "${scriptDir}/rename-cassandra-cluster.sh --qv-query \"${params.QV_QUERY_PRIMARY}\" --old-name \"${params.OLD_CLUSTER_NAME}\" --new-name \"${params.NEW_CLUSTER_NAME}\""
                        } else {
                            error "Unknown operation: ${operation}"
                        }
                    }
                }
            }
        }
    }
    
    post {
        always {
            echo 'Operation finished.'
            // Add notifications (Slack, Email, etc.) here
        }
    }
}
