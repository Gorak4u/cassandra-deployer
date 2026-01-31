// This file is managed by Puppet.
// This Jenkinsfile creates a unified, parameterized pipeline for all Cassandra cluster operations.

pipeline {
    agent { label 'cassandra-ops' } // Use your dedicated agent label

    // All scripts are assumed to be on the Jenkins agent at this path.
    // This is for environments not using Git SCM with the pipeline.
    environment {
        SCRIPTS_PATH = '/opt/cassandra-tools/scripts'
    }

    parameters {
        choice(name: 'OPERATION',
               choices: ['ROLLING_RESTART', 'ROLLING_REBOOT', 'ROLLING_PUPPET_RUN', 'JOIN_DCS', 'SPLIT_DCS', 'RENAME_CLUSTER'],
               description: 'Select the primary operation to perform.')
        
        // General Parameters
        string(name: 'QV_QUERY', defaultValue: '-r role_cassandra_pfpt -d AWSLAB', description: 'The qv query to select target nodes for most operations.')
        
        // Parameters for JOIN_DCS and SPLIT_DCS
        string(name: 'OLD_DC_QUERY', defaultValue: '', description: '[JOIN/SPLIT] The qv query for the first/old datacenter.')
        string(name: 'NEW_DC_QUERY', defaultValue: '', description: '[JOIN/SPLIT] The qv query for the second/new datacenter.')
        string(name: 'OLD_DC_NAME', defaultValue: '', description: '[JOIN/SPLIT] The Cassandra name of the first/old datacenter.')
        string(name: 'NEW_DC_NAME', defaultValue: '', description: '[JOIN/SPLIT] The Cassandra name of the second/new datacenter.')

        // Parameters for RENAME_CLUSTER
        string(name: 'OLD_CLUSTER_NAME', defaultValue: '', description: '[RENAME] The current name of the cluster.')
        string(name: 'NEW_CLUSTER_NAME', defaultValue: '', description: '[RENAME] The desired new name for the cluster.')
    }

    stages {
        // Stage 1: Rolling Restart Operation
        stage('Rolling Restart') {
            when { expression { params.OPERATION == 'ROLLING_RESTART' } }
            steps {
                sshagent(credentials: ['your-jenkins-ssh-key-id']) {
                    sh """
                        #!/bin/bash -ex
                        # Ensure scripts are executable before running
                        chmod +x ${env.SCRIPTS_PATH}/*.sh
                        ${env.SCRIPTS_PATH}/cassy.sh --rolling-op restart --qv-query "${params.QV_QUERY}"
                    """
                }
            }
        }

        // Stage 2: Rolling Reboot Operation
        stage('Rolling Reboot') {
            when { expression { params.OPERATION == 'ROLLING_REBOOT' } }
            steps {
                sshagent(credentials: ['your-jenkins-ssh-key-id']) {
                    sh """
                        #!/bin/bash -ex
                        chmod +x ${env.SCRIPTS_PATH}/*.sh
                        ${env.SCRIPTS_PATH}/cassy.sh --rolling-op reboot --qv-query "${params.QV_QUERY}"
                    """
                }
            }
        }

        // Stage 3: Rolling Puppet Run
        stage('Rolling Puppet Run') {
            when { expression { params.OPERATION == 'ROLLING_PUPPET_RUN' } }
            steps {
                sshagent(credentials: ['your-jenkins-ssh-key-id']) {
                    sh """
                        #!/bin/bash -ex
                        chmod +x ${env.SCRIPTS_PATH}/*.sh
                        ${env.SCRIPTS_PATH}/cassy.sh --rolling-op puppet --qv-query "${params.QV_QUERY}"
                    """
                }
            }
        }

        // Stage 4: Join Datacenters
        stage('Join Datacenters') {
            when { expression { params.OPERATION == 'JOIN_DCS' } }
            steps {
                sshagent(credentials: ['your-jenkins-ssh-key-id']) {
                    sh """
                        #!/bin/bash -ex
                        chmod +x ${env.SCRIPTS_PATH}/*.sh
                        ${env.SCRIPTS_PATH}/join-cassandra-dcs.sh \\
                            --old-dc-query "${params.OLD_DC_QUERY}" \\
                            --new-dc-query "${params.NEW_DC_QUERY}" \\
                            --old-dc-name "${params.OLD_DC_NAME}" \\
                            --new-dc-name "${params.NEW_DC_NAME}"
                    """
                }
            }
        }

        // Stage 5: Split Datacenters
        stage('Split Datacenters') {
            when { expression { params.OPERATION == 'SPLIT_DCS' } }
            steps {
                sshagent(credentials: ['your-jenkins-ssh-key-id']) {
                    sh """
                        #!/bin/bash -ex
                        chmod +x ${env.SCRIPTS_PATH}/*.sh
                        ${env.SCRIPTS_PATH}/split-cassandra-dcs.sh \\
                            --dc1-query "${params.OLD_DC_QUERY}" \\
                            --dc2-query "${params.NEW_DC_QUERY}" \\
                            --dc1-name "${params.OLD_DC_NAME}" \\
                            --dc2-name "${params.NEW_DC_NAME}"
                    """
                }
            }
        }

        // Stage 6: Rename Cluster
        stage('Rename Cluster') {
            when { expression { params.OPERATION == 'RENAME_CLUSTER' } }
            steps {
                sshagent(credentials: ['your-jenkins-ssh-key-id']) {
                    sh """
                        #!/bin/bash -ex
                        chmod +x ${env.SCRIPTS_PATH}/*.sh
                        ${env.SCRIPTS_PATH}/rename-cassandra-cluster.sh \\
                            --qv-query "${params.QV_QUERY}" \\
                            --old-name "${params.OLD_CLUSTER_NAME}" \\
                            --new-name "${params.NEW_CLUSTER_NAME}"
                    """
                }
            }
        }
    }
    
    post {
        always {
            echo "Cassandra operation job finished."
            // Add notifications (Slack, Email, etc.) here
        }
    }
}
