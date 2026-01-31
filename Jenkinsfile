// Jenkinsfile
pipeline {
    // This pipeline assumes the Jenkins agent has passwordless SSH access
    // to the target Cassandra nodes for the specified user.
    // The `qv`, `jq`, and all necessary scripts must be available on the agent.
    agent any

    environment {
        // --- IMPORTANT: UPDATE THIS PATH if it changes ---
        // Specify the absolute path to your scripts directory on the Jenkins agent.
        SCRIPTS_PATH = '/Users/ggonda/cassandra-tools/scripts'

        // --- IMPORTANT: UPDATE THIS PATH if needed ---
        // For macOS, Homebrew and other tools install to /usr/local/bin or /opt/homebrew/bin.
        // Jenkins has a minimal PATH, so we must add these locations for it to find `qv`.
        PATH = "/usr/local/bin:/opt/homebrew/bin:${env.PATH}"
    }

    parameters {
        choice(
            name: 'OPERATION',
            choices: [
                'ROLLING_RESTART',
                'ROLLING_REBOOT',
                'ROLLING_PUPPET_RUN',
                'JOIN_DCS',
                'SPLIT_DCS',
                'RENAME_CLUSTER',
            ],
            description: 'Select the Cassandra operation to perform.'
        )
        string(name: 'QV_QUERY', defaultValue: '', description: 'qv query to select target nodes (e.g., "-r role_cassandra_pfpt -d AWSLAB"). Used by most operations.')
        string(name: 'OLD_DC_QUERY', defaultValue: '', description: 'qv query for the OLD datacenter (for JOIN_DCS).')
        string(name: 'NEW_DC_QUERY', defaultValue: '', description: 'qv query for the NEW datacenter (for JOIN_DCS).')
        string(name: 'DC1_QUERY', defaultValue: '', description: 'qv query for the first datacenter (for SPLIT_DCS).')
        string(name: 'DC2_QUERY', defaultValue: '', description: 'qv query for the second datacenter (for SPLIT_DCS).')
        string(name: 'OLD_DC_NAME', defaultValue: '', description: 'Name of the old datacenter (for JOIN_DCS).')
        string(name: 'NEW_DC_NAME', defaultValue: '', description: 'Name of the new datacenter (for JOIN_DCS).')
        string(name: 'DC1_NAME', defaultValue: '', description: 'Name of the first datacenter (for SPLIT_DCS).')
        string(name: 'DC2_NAME', defaultValue: '', description: 'Name of the second datacenter (for SPLIT_DCS).')
        string(name: 'OLD_CLUSTER_NAME', defaultValue: '', description: 'Current cluster name (for RENAME_CLUSTER).')
        string(name: 'NEW_CLUSTER_NAME', defaultValue: '', description: 'Desired new cluster name (for RENAME_CLUSTER).')
    }

    stages {
        stage('Validate Scripts') {
            steps {
                script {
                    // Check that the core orchestration script is present and executable.
                    sh "test -x ${env.SCRIPTS_PATH}/cassy.sh"
                }
            }
        }
        
        stage('Rolling Restart') {
            when { expression { params.OPERATION == 'ROLLING_RESTART' } }
            steps {
                sshagent(credentials: ['your-jenkins-ssh-key-id']) { // <-- IMPORTANT: Change to your Jenkins credential ID
                    sh """
                        ${env.SCRIPTS_PATH}/cassy.sh --rolling-op restart --qv-query "${params.QV_QUERY}"
                    """
                }
            }
        }

        stage('Rolling Reboot') {
            when { expression { params.OPERATION == 'ROLLING_REBOOT' } }
            steps {
                sshagent(credentials: ['your-jenkins-ssh-key-id']) {
                    sh """
                        ${env.SCRIPTS_PATH}/cassy.sh --rolling-op reboot --qv-query "${params.QV_QUERY}"
                    """
                }
            }
        }

        stage('Rolling Puppet Run') {
            when { expression { params.OPERATION == 'ROLLING_PUPPET_RUN' } }
            steps {
                sshagent(credentials: ['your-jenkins-ssh-key-id']) {
                    sh """
                        ${env.SCRIPTS_PATH}/cassy.sh --rolling-op puppet --qv-query "${params.QV_QUERY}"
                    """
                }
            }
        }

        stage('Join Datacenters') {
            when { expression { params.OPERATION == 'JOIN_DCS' } }
            steps {
                sshagent(credentials: ['your-jenkins-ssh-key-id']) {
                    sh """
                        ${env.SCRIPTS_PATH}/join-cassandra-dcs.sh \\
                            --old-dc-query "${params.OLD_DC_QUERY}" \\
                            --new-dc-query "${params.NEW_DC_QUERY}" \\
                            --old-dc-name "${params.OLD_DC_NAME}" \\
                            --new-dc-name "${params.NEW_DC_NAME}" \\
                            --cassy-path "${env.SCRIPTS_PATH}/cassy.sh"
                    """
                }
            }
        }

        stage('Split Datacenters') {
            when { expression { params.OPERATION == 'SPLIT_DCS' } }
            steps {
                sshagent(credentials: ['your-jenkins-ssh-key-id']) {
                    sh """
                        ${env.SCRIPTS_PATH}/split-cassandra-dcs.sh \\
                            --dc1-query "${params.DC1_QUERY}" \\
                            --dc2-query "${params.DC2_QUERY}" \\
                            --dc1-name "${params.DC1_NAME}" \\
                            --dc2-name "${params.DC2_NAME}" \\
                            --cassy-path "${env.SCRIPTS_PATH}/cassy.sh"
                    """
                }
            }
        }

        stage('Rename Cluster') {
            when { expression { params.OPERATION == 'RENAME_CLUSTER' } }
            steps {
                sshagent(credentials: ['your-jenkins-ssh-key-id']) {
                    sh """
                        ${env.SCRIPTS_PATH}/rename-cassandra-cluster.sh \\
                            --qv-query "${params.QV_QUERY}" \\
                            --old-name "${params.OLD_CLUSTER_NAME}" \\
                            --new-name "${params.NEW_CLUSTER_NAME}" \\
                            --cassy-path "${env.SCRIPTS_PATH}/cassy.sh"
                    """
                }
            }
        }
    }

    post {
        always {
            echo 'Cassandra operation job finished.'
            // Add notifications (Slack, Email, etc.) here.
        }
    }
}
