// This file is managed by Puppet. Do not edit manually.

def createPipelineJob(String jobName, String description, String jenkinsfileContent) {
    pipelineJob("Cassandra/${jobName}") {
        description(description)
        definition {
            cps {
                script(jenkinsfileContent)
                sandbox()
            }
        }
    }
}

// --- Jenkinsfile for ROLLING RESTART ---
def jenkinsfileRestart = '''
pipeline {
    agent any

    parameters {
        choice(name: 'NODE_SELECTION_METHOD', choices: ['QV_QUERY', 'NODE_LIST'], description: 'Select nodes using a QV query or a direct list.')
        string(name: 'QV_QUERY', defaultValue: '-r role_cassandra_pfpt', description: 'The qv query to select target nodes. Used if NODE_SELECTION_METHOD is QV_QUERY.')
        string(name: 'NODE_LIST', defaultValue: '', description: 'A comma-separated list of nodes. Used if NODE_SELECTION_METHOD is NODE_LIST.')
    }

    environment {
        SCRIPTS_PATH = '/Users/ggonda/cassandra-tools/scripts'
        PATH = "/usr/local/bin:/opt/homebrew/bin:${env.PATH}"
    }

    stages {
        stage('Execute Rolling Restart') {
            steps {
                script {
                    def nodeOpts = ''
                    if (params.NODE_SELECTION_METHOD == 'QV_QUERY') {
                        nodeOpts = "--qv-query \\"${params.QV_QUERY}\\""
                    } else {
                        nodeOpts = "--nodes \\"${params.NODE_LIST}\\""
                    }

                    if (nodeOpts) {
                        sh """
                            ${env.SCRIPTS_PATH}/cassy.sh --rolling-op restart ${nodeOpts}
                        """
                    } else {
                        error("No nodes specified. Please provide a QV_QUERY or a NODE_LIST.")
                    }
                }
            }
        }
    }
}
'''
createPipelineJob('Cassandra - Restart', 'Performs a safe, rolling restart of the Cassandra service on specified nodes.', jenkinsfileRestart)


// --- Jenkinsfile for ROLLING REBOOT ---
def jenkinsfileReboot = '''
pipeline {
    agent any
    parameters {
        choice(name: 'NODE_SELECTION_METHOD', choices: ['QV_QUERY', 'NODE_LIST'], description: 'Select nodes using a QV query or a direct list.')
        string(name: 'QV_QUERY', defaultValue: '-r role_cassandra_pfpt', description: 'The qv query to select target nodes. Used if NODE_SELECTION_METHOD is QV_QUERY.')
        string(name: 'NODE_LIST', defaultValue: '', description: 'A comma-separated list of nodes. Used if NODE_SELECTION_METHOD is NODE_LIST.')
    }
    environment {
        SCRIPTS_PATH = '/Users/ggonda/cassandra-tools/scripts'
        PATH = "/usr/local/bin:/opt/homebrew/bin:${env.PATH}"
    }
    stages {
        stage('Execute Rolling Reboot') {
            steps {
                script {
                    def nodeOpts = ''
                    if (params.NODE_SELECTION_METHOD == 'QV_QUERY') {
                        nodeOpts = "--qv-query \\"${params.QV_QUERY}\\""
                    } else {
                        nodeOpts = "--nodes \\"${params.NODE_LIST}\\""
                    }

                    if (nodeOpts) {
                        sh """
                            ${env.SCRIPTS_PATH}/cassy.sh --rolling-op reboot ${nodeOpts}
                        """
                    } else {
                        error("No nodes specified. Please provide a QV_QUERY or a NODE_LIST.")
                    }
                }
            }
        }
    }
}
'''
createPipelineJob('Cassandra - Reboot', 'Performs a safe, rolling reboot of the specified nodes.', jenkinsfileReboot)


// --- Jenkinsfile for ROLLING PUPPET-RUN ---
def jenkinsfilePuppet = '''
pipeline {
    agent any
    parameters {
        choice(name: 'NODE_SELECTION_METHOD', choices: ['QV_QUERY', 'NODE_LIST'], description: 'Select nodes using a QV query or a direct list.')
        string(name: 'QV_QUERY', defaultValue: '-r role_cassandra_pfpt', description: 'The qv query to select target nodes. Used if NODE_SELECTION_METHOD is QV_QUERY.')
        string(name: 'NODE_LIST', defaultValue: '', description: 'A comma-separated list of nodes. Used if NODE_SELECTION_METHOD is NODE_LIST.')
    }
    environment {
        SCRIPTS_PATH = '/Users/ggonda/cassandra-tools/scripts'
        PATH = "/usr/local/bin:/opt/homebrew/bin:${env.PATH}"
    }
    stages {
        stage('Execute Rolling Puppet Run') {
            steps {
                script {
                    def nodeOpts = ''
                    if (params.NODE_SELECTION_METHOD == 'QV_QUERY') {
                        nodeOpts = "--qv-query \\"${params.QV_QUERY}\\""
                    } else {
                        nodeOpts = "--nodes \\"${params.NODE_LIST}\\""
                    }

                    if (nodeOpts) {
                        sh """
                            ${env.SCRIPTS_PATH}/cassy.sh --rolling-op puppet ${nodeOpts}
                        """
                    } else {
                        error("No nodes specified. Please provide a QV_QUERY or a NODE_LIST.")
                    }
                }
            }
        }
    }
}
'''
createPipelineJob('Cassandra - Puppet-run', 'Performs a safe, rolling Puppet run on the specified nodes.', jenkinsfilePuppet)


// --- Jenkinsfile for GENERIC COMMAND ---
def jenkinsfileCommand = '''
pipeline {
    agent any
    parameters {
        choice(name: 'NODE_SELECTION_METHOD', choices: ['QV_QUERY', 'NODE_LIST'], description: 'Select nodes using a QV query or a direct list.')
        string(name: 'QV_QUERY', defaultValue: '-r role_cassandra_pfpt', description: 'The qv query to select target nodes.')
        string(name: 'NODE_LIST', defaultValue: '', description: 'A comma-separated list of nodes.')
        string(name: 'CASSY_COMMAND', defaultValue: 'sudo /usr/local/bin/cass-ops health', description: 'The command to execute on each node.')
        booleanParam(name: 'PARALLEL_EXEC', defaultValue: false, description: 'Run in parallel?')
    }
    environment {
        SCRIPTS_PATH = '/Users/ggonda/cassandra-tools/scripts'
        PATH = "/usr/local/bin:/opt/homebrew/bin:${env.PATH}"
    }
    stages {
        stage('Execute Command') {
            steps {
                script {
                    def nodeOpts = ''
                    if (params.NODE_SELECTION_METHOD == 'QV_QUERY') {
                        nodeOpts = "--qv-query \\"${params.QV_QUERY}\\""
                    } else {
                        nodeOpts = "--nodes \\"${params.NODE_LIST}\\""
                    }
                    def parallelFlag = params.PARALLEL_EXEC ? '--parallel' : ''

                    if (nodeOpts) {
                        sh """
                            ${env.SCRIPTS_PATH}/cassy.sh -c "${params.CASSY_COMMAND}" ${nodeOpts} ${parallelFlag}
                        """
                    } else {
                        error("No nodes specified.")
                    }
                }
            }
        }
    }
}
'''
createPipelineJob('Cassandra - Command', 'Runs a generic command on specified nodes.', jenkinsfileCommand)


// --- Jenkinsfile for JOIN DATACENTERS ---
def jenkinsfileJoin = '''
pipeline {
    agent any
    parameters {
        choice(name: 'NODE_SELECTION_METHOD', choices: ['QV_QUERY', 'NODE_LIST'], description: 'Select nodes using a QV query or a direct list.')
        string(name: 'OLD_DC_QV_QUERY', defaultValue: '', description: 'QV query for the existing DC.')
        string(name: 'NEW_DC_QV_QUERY', defaultValue: '', description: 'QV query for the new DC.')
        string(name: 'OLD_DC_NODE_LIST', defaultValue: '', description: 'Node list for the existing DC.')
        string(name: 'NEW_DC_NODE_LIST', defaultValue: '', description: 'Node list for the new DC.')
        string(name: 'OLD_DC_NAME', defaultValue: '', description: 'Cassandra name of the existing DC (e.g., dc1).')
        string(name: 'NEW_DC_NAME', defaultValue: '', description: 'Cassandra name of the new DC (e.g., dc2).')
    }
    environment {
        SCRIPTS_PATH = '/Users/ggonda/cassandra-tools/scripts'
        PATH = "/usr/local/bin:/opt/homebrew/bin:${env.PATH}"
    }
    stages {
        stage('Join Datacenters') {
            steps {
                script {
                    def oldDcOpts = ''
                    def newDcOpts = ''
                    if (params.NODE_SELECTION_METHOD == 'QV_QUERY') {
                        oldDcOpts = "--old-dc-query \\"${params.OLD_DC_QV_QUERY}\\""
                        newDcOpts = "--new-dc-query \\"${params.NEW_DC_QV_QUERY}\\""
                    } else {
                        oldDcOpts = "--old-dc-nodes \\"${params.OLD_DC_NODE_LIST}\\""
                        newDcOpts = "--new-dc-nodes \\"${params.NEW_DC_NODE_LIST}\\""
                    }
                    
                    sh """
                        ${env.SCRIPTS_PATH}/join-cassandra-dcs.sh \\
                            ${oldDcOpts} \\
                            ${newDcOpts} \\
                            --old-dc-name "${params.OLD_DC_NAME}" \\
                            --new-dc-name "${params.NEW_DC_NAME}"
                    """
                }
            }
        }
    }
}
'''
createPipelineJob('Cassandra - Join', 'Orchestrates joining a new Cassandra DC to an existing one.', jenkinsfileJoin)


// --- Jenkinsfile for SPLIT DATACENTERS ---
def jenkinsfileSplit = '''
pipeline {
    agent any
    parameters {
        choice(name: 'NODE_SELECTION_METHOD', choices: ['QV_QUERY', 'NODE_LIST'], description: 'Select nodes using a QV query or a direct list.')
        string(name: 'DC1_QV_QUERY', defaultValue: '', description: 'QV query for the first DC.')
        string(name: 'DC2_QV_QUERY', defaultValue: '', description: 'QV query for the second DC.')
        string(name: 'DC1_NODE_LIST', defaultValue: '', description: 'Node list for the first DC.')
        string(name: 'DC2_NODE_LIST', defaultValue: '', description: 'Node list for the second DC.')
        string(name: 'DC1_NAME', defaultValue: '', description: 'Cassandra name of the first DC.')
        string(name: 'DC2_NAME', defaultValue: '', description: 'Cassandra name of the second DC.')
    }
    environment {
        SCRIPTS_PATH = '/Users/ggonda/cassandra-tools/scripts'
        PATH = "/usr/local/bin:/opt/homebrew/bin:${env.PATH}"
    }
    stages {
        stage('Split Datacenters') {
            steps {
                script {
                    def dc1Opts = ''
                    def dc2Opts = ''
                    if (params.NODE_SELECTION_METHOD == 'QV_QUERY') {
                        dc1Opts = "--dc1-query \\"${params.DC1_QV_QUERY}\\""
                        dc2Opts = "--dc2-query \\"${params.DC2_QV_QUERY}\\""
                    } else {
                        dc1Opts = "--dc1-nodes \\"${params.DC1_NODE_LIST}\\""
                        dc2Opts = "--dc2-nodes \\"${params.DC2_NODE_LIST}\\""
                    }
                    
                    sh """
                        ${env.SCRIPTS_PATH}/split-cassandra-dcs.sh \\
                            ${dc1Opts} \\
                            ${dc2Opts} \\
                            --dc1-name "${params.DC1_NAME}" \\
                            --dc2-name "${params.DC2_NAME}"
                    """
                }
            }
        }
    }
}
'''
createPipelineJob('Cassandra - Split', 'Orchestrates splitting a multi-DC cluster into two separate clusters.', jenkinsfileSplit)


// --- Jenkinsfile for RENAME CLUSTER ---
def jenkinsfileRename = '''
pipeline {
    agent any
    parameters {
        choice(name: 'NODE_SELECTION_METHOD', choices: ['QV_QUERY', 'NODE_LIST'], description: 'Select nodes using a QV query or a direct list.')
        string(name: 'QV_QUERY', defaultValue: '', description: 'QV query for all nodes in the cluster.')
        string(name: 'NODE_LIST', defaultValue: '', description: 'A comma-separated list of all nodes in the cluster.')
        string(name: 'OLD_NAME', defaultValue: '', description: 'The current cluster name.')
        string(name: 'NEW_NAME', defaultValue: '', description: 'The desired new cluster name.')
    }
    environment {
        SCRIPTS_PATH = '/Users/ggonda/cassandra-tools/scripts'
        PATH = "/usr/local/bin:/opt/homebrew/bin:${env.PATH}"
    }
    stages {
        stage('Rename Cluster') {
            steps {
                script {
                    def nodeOpts = ''
                    if (params.NODE_SELECTION_METHOD == 'QV_QUERY') {
                        nodeOpts = "--qv-query \\"${params.QV_QUERY}\\""
                    } else {
                        nodeOpts = "--nodes \\"${params.NODE_LIST}\\""
                    }

                    sh """
                        ${env.SCRIPTS_PATH}/rename-cassandra-cluster.sh \\
                            ${nodeOpts} \\
                            --old-name "${params.OLD_NAME}" \\
                            --new-name "${params.NEW_NAME}"
                    """
                }
            }
        }
    }
}
'''
createPipelineJob('Cassandra - Rename', 'Orchestrates a full cluster rename (requires downtime).', jenkinsfileRename)

// --- Jenkinsfile for COMPACTION ---
def jenkinsfileCompaction = '''
pipeline {
    agent any
    parameters {
        choice(name: 'NODE_SELECTION_METHOD', choices: ['QV_QUERY', 'NODE_LIST'], description: 'Select nodes using a QV query or a direct list.')
        string(name: 'QV_QUERY', defaultValue: '', description: 'QV query for target nodes.')
        string(name: 'NODE_LIST', defaultValue: '', description: 'A comma-separated list of nodes.')
        choice(name: 'SCOPE', choices: ['ENTIRE_NODE', 'keyspace', 'tables'], description: 'The scope of the compaction.')
        string(name: 'KEYSPACE_NAME', defaultValue: '', description: 'Keyspace name (required for keyspace or table scope).')
        string(name: 'TABLE_NAMES', defaultValue: '', description: 'Comma-separated list of table names (used for table scope).')
        string(name: 'NODETOOL_OPTIONS', defaultValue: '', trim: true, description: 'Optional: Extra options to pass to nodetool compact (e.g., --split-output).')
        booleanParam(name: 'PARALLEL_EXEC', defaultValue: false, description: 'Run in parallel on all specified nodes?')
    }
    environment {
        SCRIPTS_PATH = '/Users/ggonda/cassandra-tools/scripts'
        PATH = "/usr/local/bin:/opt/homebrew/bin:${env.PATH}"
    }
    stages {
        stage('Execute Compaction') {
            steps {
                script {
                    def nodeOpts = ''
                    if (params.NODE_SELECTION_METHOD == 'QV_QUERY') {
                        nodeOpts = "--qv-query \\"${params.QV_QUERY}\\""
                    } else {
                        nodeOpts = "--nodes \\"${params.NODE_LIST}\\""
                    }

                    def scopeOpts = ''
                    if (params.SCOPE == 'keyspace') {
                        scopeOpts = "-k ${params.KEYSPACE_NAME}"
                    } else if (params.SCOPE == 'tables') {
                        scopeOpts = "-k ${params.KEYSPACE_NAME} -t '${params.TABLE_NAMES.replace(',', ' -t ')}'"
                    }
                    
                    def nodetoolOpts = params.NODETOOL_OPTIONS ? "--nodetool-options \\"${params.NODETOOL_OPTIONS}\\"" : ""
                    def parallelFlag = params.PARALLEL_EXEC ? '--parallel' : ''
                    
                    def command = "sudo /usr/local/bin/compaction-manager.sh ${scopeOpts} ${nodetoolOpts}"

                    sh """
                        ${env.SCRIPTS_PATH}/cassy.sh -c "${command}" ${nodeOpts} ${parallelFlag}
                    """
                }
            }
        }
    }
}
'''
createPipelineJob('Cassandra - Compaction', 'Runs nodetool compact on specified nodes/keyspaces/tables.', jenkinsfileCompaction)

// --- Jenkinsfile for GARBAGE COLLECT ---
def jenkinsfileGarbageCollect = '''
pipeline {
    agent any
    parameters {
        choice(name: 'NODE_SELECTION_METHOD', choices: ['QV_QUERY', 'NODE_LIST'], description: 'Select nodes using a QV query or a direct list.')
        string(name: 'QV_QUERY', defaultValue: '', description: 'QV query for target nodes.')
        string(name: 'NODE_LIST', defaultValue: '', description: 'A comma-separated list of nodes.')
        choice(name: 'SCOPE', choices: ['ENTIRE_NODE', 'keyspace', 'tables'], description: 'The scope of the garbage collection.')
        string(name: 'KEYSPACE_NAME', defaultValue: '', description: 'Keyspace name (required for keyspace or table scope).')
        string(name: 'TABLE_NAMES', defaultValue: '', description: 'Comma-separated list of table names (used for table scope).')
        string(name: 'NODETOOL_OPTIONS', defaultValue: '', trim: true, description: 'Optional: Extra options to pass to nodetool garbagecollect (e.g., -g CELL -j 2).')
        booleanParam(name: 'PARALLEL_EXEC', defaultValue: false, description: 'Run in parallel on all specified nodes?')
    }
    environment {
        SCRIPTS_PATH = '/Users/ggonda/cassandra-tools/scripts'
        PATH = "/usr/local/bin:/opt/homebrew/bin:${env.PATH}"
    }
    stages {
        stage('Execute Garbage Collection') {
            steps {
                script {
                    def nodeOpts = ''
                    if (params.NODE_SELECTION_METHOD == 'QV_QUERY') {
                        nodeOpts = "--qv-query \\"${params.QV_QUERY}\\""
                    } else {
                        nodeOpts = "--nodes \\"${params.NODE_LIST}\\""
                    }

                    def scopeOpts = ''
                    if (params.SCOPE == 'keyspace') {
                        scopeOpts = "-k ${params.KEYSPACE_NAME}"
                    } else if (params.SCOPE == 'tables') {
                        scopeOpts = "-k ${params.KEYSPACE_NAME} -t '${params.TABLE_NAMES.replace(',', ' -t ')}'"
                    }

                    def nodetoolOpts = params.NODETOOL_OPTIONS ? "--nodetool-options \\"${params.NODETOOL_OPTIONS}\\"" : ""
                    def parallelFlag = params.PARALLEL_EXEC ? '--parallel' : ''
                    
                    def command = "sudo /usr/local/bin/garbage-collect.sh ${scopeOpts} ${nodetoolOpts}"

                    sh """
                        ${env.SCRIPTS_PATH}/cassy.sh -c "${command}" ${nodeOpts} ${parallelFlag}
                    """
                }
            }
        }
    }
}
'''
createPipelineJob('Cassandra - Garbage-Collect', 'Runs nodetool garbagecollect on specified nodes/keyspaces/tables.', jenkinsfileGarbageCollect)
