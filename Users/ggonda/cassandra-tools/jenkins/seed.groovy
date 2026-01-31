// A map holding the content of each Jenkinsfile.
// This avoids reading from the filesystem, which is blocked by Jenkins security sandbox.
def jobScripts = [
  "Reboot": '''
pipeline {
    agent any

    environment {
        // Set the path to your scripts directory on the Jenkins agent
        SCRIPTS_PATH = '/Users/ggonda/cassandra-tools/scripts'
        // Add common macOS paths for tools like 'qv'
        PATH = "/opt/homebrew/bin:/usr/local/bin:${env.PATH}"
    }

    parameters {
        choice(name: 'NODE_SELECTION_METHOD', choices: ['QV_QUERY', 'NODE_LIST'], description: 'Select nodes using a qv query or a direct list.')
        string(name: 'QV_QUERY', defaultValue: '-r role_cassandra_pfpt', description: 'The qv query to select target nodes. Used if method is QV_QUERY.')
        string(name: 'NODE_LIST', defaultValue: '', description: 'A comma-separated list of nodes. Used if method is NODE_LIST.')
    }

    stages {
        stage('Execute Rolling Reboot') {
            steps {
                script {
                    def node_arg = ''
                    if (params.NODE_SELECTION_METHOD == 'QV_QUERY') {
                        node_arg = "--qv-query \\"${params.QV_QUERY}\\""
                    } else {
                        node_arg = "--nodes \\"${params.NODE_LIST}\\""
                    }
                    
                    sh """
                        chmod +x ${env.SCRIPTS_PATH}/cassy.sh
                        ${env.SCRIPTS_PATH}/cassy.sh --rolling-op reboot ${node_arg}
                    """
                }
            }
        }
    }
}
''',
  "Restart": '''
pipeline {
    agent any

    environment {
        // Set the path to your scripts directory on the Jenkins agent
        SCRIPTS_PATH = '/Users/ggonda/cassandra-tools/scripts'
        // Add common macOS paths for tools like 'qv'
        PATH = "/opt/homebrew/bin:/usr/local/bin:${env.PATH}"
    }

    parameters {
        choice(name: 'NODE_SELECTION_METHOD', choices: ['QV_QUERY', 'NODE_LIST'], description: 'Select nodes using a qv query or a direct list.')
        string(name: 'QV_QUERY', defaultValue: '-r role_cassandra_pfpt', description: 'The qv query to select target nodes. Used if method is QV_QUERY.')
        string(name: 'NODE_LIST', defaultValue: '', description: 'A comma-separated list of nodes. Used if method is NODE_LIST.')
    }

    stages {
        stage('Execute Rolling Restart') {
            steps {
                script {
                    def node_arg = ''
                    if (params.NODE_SELECTION_METHOD == 'QV_QUERY') {
                        node_arg = "--qv-query \\"${params.QV_QUERY}\\""
                    } else {
                        node_arg = "--nodes \\"${params.NODE_LIST}\\""
                    }
                    
                    sh """
                        chmod +x ${env.SCRIPTS_PATH}/cassy.sh
                        ${env.SCRIPTS_PATH}/cassy.sh --rolling-op restart ${node_arg}
                    """
                }
            }
        }
    }
}
''',
  "Join": '''
pipeline {
    agent any

    environment {
        // Set the path to your scripts directory on the Jenkins agent
        SCRIPTS_PATH = '/Users/ggonda/cassandra-tools/scripts'
        // Add common macOS paths for tools like 'qv'
        PATH = "/opt/homebrew/bin:/usr/local/bin:${env.PATH}"
    }

    parameters {
        string(name: 'OLD_DC_NAME', description: 'The Cassandra name of the existing datacenter (e.g., us-east-1).')
        string(name: 'NEW_DC_NAME', description: 'The Cassandra name of the new datacenter to be joined (e.g., eu-west-1).')
        
        choice(name: 'OLD_DC_NODE_METHOD', choices: ['QV_QUERY', 'NODE_LIST'], description: 'Select OLD DC nodes using a qv query or a direct list.')
        string(name: 'OLD_DC_QV_QUERY', defaultValue: '-r role_cassandra_pfpt -d <old_dc_name>', description: 'The qv query for the OLD datacenter nodes.')
        string(name: 'OLD_DC_NODE_LIST', defaultValue: '', description: 'A comma-separated list of OLD datacenter nodes.')

        choice(name: 'NEW_DC_NODE_METHOD', choices: ['QV_QUERY', 'NODE_LIST'], description: 'Select NEW DC nodes using a qv query or a direct list.')
        string(name: 'NEW_DC_QV_QUERY', defaultValue: '-r role_cassandra_pfpt -d <new_dc_name>', description: 'The qv query for the NEW datacenter nodes.')
        string(name: 'NEW_DC_NODE_LIST', defaultValue: '', description: 'A comma-separated list of NEW datacenter nodes.')
    }

    stages {
        stage('Execute Join Datacenters') {
            steps {
                script {
                    def old_dc_arg = ''
                    if (params.OLD_DC_NODE_METHOD == 'QV_QUERY') {
                        old_dc_arg = "--old-dc-query \\"${params.OLD_DC_QV_QUERY}\\""
                    } else {
                        old_dc_arg = "--old-dc-nodes \\"${params.OLD_DC_NODE_LIST}\\""
                    }

                    def new_dc_arg = ''
                    if (params.NEW_DC_NODE_METHOD == 'QV_QUERY') {
                        new_dc_arg = "--new-dc-query \\"${params.NEW_DC_QV_QUERY}\\""
                    } else {
                        new_dc_arg = "--new-dc-nodes \\"${params.NEW_DC_NODE_LIST}\\""
                    }

                    sh """
                        chmod +x ${env.SCRIPTS_PATH}/join-cassandra-dcs.sh
                        ${env.SCRIPTS_PATH}/join-cassandra-dcs.sh \\
                            ${old_dc_arg} \\
                            ${new_dc_arg} \\
                            --old-dc-name "${params.OLD_DC_NAME}" \\
                            --new-dc-name "${params.NEW_DC_NAME}"
                    """
                }
            }
        }
    }
}
''',
  "Split": '''
pipeline {
    agent any

    environment {
        // Set the path to your scripts directory on the Jenkins agent
        SCRIPTS_PATH = '/Users/ggonda/cassandra-tools/scripts'
        // Add common macOS paths for tools like 'qv'
        PATH = "/opt/homebrew/bin:/usr/local/bin:${env.PATH}"
    }

    parameters {
        string(name: 'DC1_NAME', description: 'The Cassandra name of the first datacenter (e.g., us-east-1).')
        string(name: 'DC2_NAME', description: 'The Cassandra name of the second datacenter to be split off (e.g., eu-west-1).')

        choice(name: 'DC1_NODE_METHOD', choices: ['QV_QUERY', 'NODE_LIST'], description: 'Select DC1 nodes using a qv query or a direct list.')
        string(name: 'DC1_QV_QUERY', defaultValue: '-r role_cassandra_pfpt -d <dc1_name>', description: 'The qv query for DC1 nodes.')
        string(name: 'DC1_NODE_LIST', defaultValue: '', description: 'A comma-separated list of DC1 nodes.')

        choice(name: 'DC2_NODE_METHOD', choices: ['QV_QUERY', 'NODE_LIST'], description: 'Select DC2 nodes using a qv query or a direct list.')
        string(name: 'DC2_QV_QUERY', defaultValue: '-r role_cassandra_pfpt -d <dc2_name>', description: 'The qv query for DC2 nodes.')
        string(name: 'DC2_NODE_LIST', defaultValue: '', description: 'A comma-separated list of DC2 nodes.')
    }

    stages {
        stage('Execute Split Datacenters') {
            steps {
                script {
                    def dc1_arg = ''
                    if (params.DC1_NODE_METHOD == 'QV_QUERY') {
                        dc1_arg = "--dc1-query \\"${params.DC1_QV_QUERY}\\""
                    } else {
                        dc1_arg = "--dc1-nodes \\"${params.DC1_NODE_LIST}\\""
                    }

                    def dc2_arg = ''
                    if (params.DC2_NODE_METHOD == 'QV_QUERY') {
                        dc2_arg = "--dc2-query \\"${params.DC2_QV_QUERY}\\""
                    } else {
                        dc2_arg = "--dc2-nodes \\"${params.DC2_NODE_LIST}\\""
                    }
                    
                    sh """
                        chmod +x ${env.SCRIPTS_PATH}/split-cassandra-dcs.sh
                        ${env.SCRIPTS_PATH}/split-cassandra-dcs.sh \\
                            ${dc1_arg} \\
                            ${dc2_arg} \\
                            --dc1-name "${params.DC1_NAME}" \\
                            --dc2-name "${params.DC2_NAME}"
                    """
                }
            }
        }
    }
}
''',
  "Rename": '''
pipeline {
    agent any

    environment {
        // Set the path to your scripts directory on the Jenkins agent
        SCRIPTS_PATH = '/Users/ggonda/cassandra-tools/scripts'
        // Add common macOS paths for tools like 'qv'
        PATH = "/opt/homebrew/bin:/usr/local/bin:${env.PATH}"
    }

    parameters {
        string(name: 'OLD_NAME', description: 'The current cluster name.')
        string(name: 'NEW_NAME', description: 'The desired new cluster name.')
        choice(name: 'NODE_SELECTION_METHOD', choices: ['QV_QUERY', 'NODE_LIST'], description: 'Select nodes using a qv query or a direct list.')
        string(name: 'QV_QUERY', defaultValue: '-r role_cassandra_pfpt', description: 'The qv query to select all nodes in the cluster.')
        string(name: 'NODE_LIST', defaultValue: '', description: 'A comma-separated list of all nodes in the cluster.')
    }

    stages {
        stage('Execute Rename Cluster') {
            steps {
                script {
                    def node_arg = ''
                    if (params.NODE_SELECTION_METHOD == 'QV_QUERY') {
                        node_arg = "--qv-query \\"${params.QV_QUERY}\\""
                    } else {
                        node_arg = "--nodes \\"${params.NODE_LIST}\\""
                    }
                
                    sh """
                        chmod +x ${env.SCRIPTS_PATH}/rename-cassandra-cluster.sh
                        ${env.SCRIPTS_PATH}/rename-cassandra-cluster.sh \\
                            ${node_arg} \\
                            --old-name "${params.OLD_NAME}" \\
                            --new-name "${params.NEW_NAME}"
                    """
                }
            }
        }
    }
}
''',
  "Puppet-run": '''
pipeline {
    agent any

    environment {
        // Set the path to your scripts directory on the Jenkins agent
        SCRIPTS_PATH = '/Users/ggonda/cassandra-tools/scripts'
        // Add common macOS paths for tools like 'qv'
        PATH = "/opt/homebrew/bin:/usr/local/bin:${env.PATH}"
    }

    parameters {
        choice(name: 'NODE_SELECTION_METHOD', choices: ['QV_QUERY', 'NODE_LIST'], description: 'Select nodes using a qv query or a direct list.')
        string(name: 'QV_QUERY', defaultValue: '-r role_cassandra_pfpt', description: 'The qv query to select target nodes.')
        string(name: 'NODE_LIST', defaultValue: '', description: 'A comma-separated list of nodes.')
    }

    stages {
        stage('Execute Rolling Puppet Run') {
            steps {
                script {
                    def node_arg = ''
                    if (params.NODE_SELECTION_METHOD == 'QV_QUERY') {
                        node_arg = "--qv-query \\"${params.QV_QUERY}\\""
                    } else {
                        node_arg = "--nodes \\"${params.NODE_LIST}\\""
                    }

                    sh """
                        chmod +x ${env.SCRIPTS_PATH}/cassy.sh
                        ${env.SCRIPTS_PATH}/cassy.sh --rolling-op puppet ${node_arg}
                    """
                }
            }
        }
    }
}
''',
  "Command": '''
pipeline {
    agent any

    environment {
        // Set the path to your scripts directory on the Jenkins agent
        SCRIPTS_PATH = '/Users/ggonda/cassandra-tools/scripts'
        // Add common macOS paths for tools like 'qv'
        PATH = "/opt/homebrew/bin:/usr/local/bin:${env.PATH}"
    }

    parameters {
        string(name: 'CASSY_COMMAND', defaultValue: 'sudo cass-ops health', description: 'The command to run on the nodes, wrapped in quotes.')
        booleanParam(name: 'PARALLEL_EXECUTION', defaultValue: false, description: 'Run in parallel on all nodes?')
        choice(name: 'NODE_SELECTION_METHOD', choices: ['QV_QUERY', 'NODE_LIST'], description: 'Select nodes using a qv query or a direct list.')
        string(name: 'QV_QUERY', defaultValue: '-r role_cassandra_pfpt', description: 'The qv query to select target nodes.')
        string(name: 'NODE_LIST', defaultValue: '', description: 'A comma-separated list of nodes.')
    }

    stages {
        stage('Execute Generic Command') {
            steps {
                script {
                    def node_arg = ''
                    if (params.NODE_SELECTION_METHOD == 'QV_QUERY') {
                        node_arg = "--qv-query \\"${params.QV_QUERY}\\""
                    } else {
                        node_arg = "--nodes \\"${params.NODE_LIST}\\""
                    }

                    def parallel_flag = params.PARALLEL_EXECUTION ? '--parallel' : ''

                    sh """
                        chmod +x ${env.SCRIPTS_PATH}/cassy.sh
                        ${env.SCRIPTS_PATH}/cassy.sh ${node_arg} -c "${params.CASSY_COMMAND}" ${parallel_flag}
                    """
                }
            }
        }
    }
}
'''
]

// Iterate over the map and create a pipeline job for each entry.
jobScripts.each { jobName, scriptContent ->
  pipelineJob("Cassandra - ${jobName}") {
    // Description for the Jenkins UI
    description("Runs the Cassandra '${jobName}' operation.")

    // Use the script content from the map
    definition {
      cps {
        script(scriptContent)
        // This is crucial: it tells Jenkins to run this script in the security sandbox.
        sandbox()
      }
    }
  }
}
