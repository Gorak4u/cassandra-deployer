// This Jenkinsfile provides a single, parameterized job for running all major
// Cassandra orchestration scripts safely from the Jenkins UI.

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
            description: 'The high-level Cassandra operation to perform.'
        )

        // Parameters for Rolling Operations & Rename
        string(name: 'QV_QUERY', defaultValue: '', description: 'Required for all Rolling Ops and Rename. The qv query to select target nodes (e.g., "-r role_cassandra_pfpt -d AWSLAB").')

        // Parameters for JOIN_DCS and SPLIT_DCS
        string(name: 'DC1_QUERY', defaultValue: '', description: 'For JOIN/SPLIT: The qv query for the first/old datacenter.')
        string(name: 'DC2_QUERY', defaultValue: '', description: 'For JOIN/SPLIT: The qv query for the second/new datacenter.')
        string(name: 'DC1_NAME', defaultValue: '', description: 'For JOIN/SPLIT: The Cassandra name of the first/old datacenter.')
        string(name: 'DC2_NAME', defaultValue: '', description: 'For JOIN/SPLIT: The Cassandra name of the second/new datacenter.')
        
        // Parameters for RENAME_CLUSTER
        string(name: 'OLD_CLUSTER_NAME', defaultValue: '', description: 'For RENAME_CLUSTER: The current name of the cluster.')
        string(name: 'NEW_CLUSTER_NAME', defaultValue: '', description: 'For RENAME_CLUSTER: The desired new name for the cluster.')
    }

    stages {
        stage('Checkout') {
            steps {
                // This assumes your Jenkins job is configured to check out from your Git repository.
                // If not, add a git step here:
                // git 'https://your-git-server/your-repo.git'
                echo 'Checking out source code...'
            }
        }

        stage('Execute Cassandra Operation') {
            steps {
                // Use the SSH Agent plugin to securely provide the SSH key for cassy.sh
                sshagent(credentials: ['your-jenkins-ssh-key-id']) {
                    script {
                        // Ensure all scripts are executable
                        sh 'chmod +x scripts/*.sh'

                        // Use if/else if to execute the correct command based on the selected operation
                        if (params.OPERATION == 'ROLLING_RESTART') {
                            if (params.QV_QUERY.isEmpty()) {
                                error("QV_QUERY parameter is required for ROLLING_RESTART.")
                            }
                            sh "./scripts/cassy.sh --rolling-op restart --qv-query \"${params.QV_QUERY}\""
                        
                        } else if (params.OPERATION == 'ROLLING_REBOOT') {
                            if (params.QV_QUERY.isEmpty()) {
                                error("QV_QUERY parameter is required for ROLLING_REBOOT.")
                            }
                            sh "./scripts/cassy.sh --rolling-op reboot --qv-query \"${params.QV_QUERY}\""

                        } else if (params.OPERATION == 'ROLLING_PUPPET_RUN') {
                            if (params.QV_QUERY.isEmpty()) {
                                error("QV_QUERY parameter is required for ROLLING_PUPPET_RUN.")
                            }
                            sh "./scripts/cassy.sh --rolling-op puppet --qv-query \"${params.QV_QUERY}\""

                        } else if (params.OPERATION == 'JOIN_DCS') {
                            if (params.DC1_QUERY.isEmpty() || params.DC2_QUERY.isEmpty() || params.DC1_NAME.isEmpty() || params.DC2_NAME.isEmpty()) {
                                error("DC1_QUERY, DC2_QUERY, DC1_NAME, and DC2_NAME parameters are required for JOIN_DCS.")
                            }
                            sh "./scripts/join-cassandra-dcs.sh --old-dc-query \"${params.DC1_QUERY}\" --new-dc-query \"${params.DC2_QUERY}\" --old-dc-name \"${params.DC1_NAME}\" --new-dc-name \"${params.DC2_NAME}\""
                        
                        } else if (params.OPERATION == 'SPLIT_DCS') {
                            if (params.DC1_QUERY.isEmpty() || params.DC2_QUERY.isEmpty() || params.DC1_NAME.isEmpty() || params.DC2_NAME.isEmpty()) {
                                error("DC1_QUERY, DC2_QUERY, DC1_NAME, and DC2_NAME parameters are required for SPLIT_DCS.")
                            }
                            sh "./scripts/split-cassandra-dcs.sh --dc1-query \"${params.DC1_QUERY}\" --dc2-query \"${params.DC2_QUERY}\" --dc1-name \"${params.DC1_NAME}\" --dc2-name \"${params.DC2_NAME}\""

                        } else if (params.OPERATION == 'RENAME_CLUSTER') {
                            if (params.QV_QUERY.isEmpty() || params.OLD_CLUSTER_NAME.isEmpty() || params.NEW_CLUSTER_NAME.isEmpty()) {
                                error("QV_QUERY, OLD_CLUSTER_NAME, and NEW_CLUSTER_NAME parameters are required for RENAME_CLUSTER.")
                            }
                            sh "./scripts/rename-cassandra-cluster.sh --qv-query \"${params.QV_QUERY}\" --old-name \"${params.OLD_CLUSTER_NAME}\" --new-name \"${params.NEW_CLUSTER_NAME}\""
                        }
                    }
                }
            }
        }
    }
    
    post {
        always {
            echo "Cassandra operation job finished."
            // Add notifications (Slack, Email, etc.) here for audit purposes
        }
    }
}
