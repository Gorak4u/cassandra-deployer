// This file is managed by Puppet. Do not edit manually.
// Jenkins Job DSL Seed Job
// For documentation on the syntax, see: https://github.com/jenkinsci/job-dsl-plugin/wiki

// The folder where all our Cassandra jobs will live.
folder('Cassandra')

// =============================================================================
//  Generic Command Runner Job
// =============================================================================
pipelineJob('Cassandra/Command') {
    description('Runs an arbitrary `cass-ops` command on a set of nodes.')
    definition {
        cps {
            script('''
                properties([
                    parameters([
                        string(name: 'OPERATION', defaultValue: 'COMMAND', description: 'Selected operation (fixed for this job).'),
                        string(name: 'NODE_SELECTION_METHOD', defaultValue: 'QV_QUERY', description: 'Method to select target nodes: QV_QUERY or NODE_LIST.'),
                        string(name: 'QV_QUERY', defaultValue: '-r role_cassandra_pfpt -d AWSLAB', description: 'The QV query to select nodes.'),
                        string(name: 'NODE_LIST', defaultValue: '', description: 'A comma-separated list of nodes.'),
                        string(name: 'CASSY_COMMAND', defaultValue: 'sudo cass-ops health', description: 'The `cass-ops` command to execute.'),
                        booleanParam(name: 'PARALLEL_EXECUTION', defaultValue: false, description: 'Run cassy.sh in parallel on all nodes?')
                    ])
                ])

                pipeline {
                    agent any
                    environment {
                        SCRIPTS_PATH = '/Users/ggonda/cassandra-tools/scripts'
                        PATH = "/opt/homebrew/bin:/usr/local/bin:${env.PATH}"
                    }
                    stages {
                        stage('Execute Command') {
                            steps {
                                script {
                                    def cassyCommand = "${env.SCRIPTS_PATH}/cassy.sh"
                                    if (params.NODE_SELECTION_METHOD == 'QV_QUERY') {
                                        cassyCommand += " --qv-query \\"${params.QV_QUERY}\\""
                                    } else {
                                        cassyCommand += " --nodes \\"${params.NODE_LIST}\\""
                                    }

                                    if (params.PARALLEL_EXECUTION) {
                                        cassyCommand += ' --parallel'
                                    }

                                    cassyCommand += " -c \\"${params.CASSY_COMMAND}\\""

                                    sh cassyCommand
                                }
                            }
                        }
                    }
                }
            '''.stripIndent())
            sandbox()
        }
    }
}

// =============================================================================
//  Join Datacenters Job
// =============================================================================
pipelineJob('Cassandra/Join') {
    description('Orchestrates joining a new Cassandra datacenter to an existing one.')
    definition {
        cps {
            script('''
                properties([
                    parameters([
                        string(name: 'OPERATION', defaultValue: 'JOIN_DCS', description: 'Selected operation (fixed for this job).'),
                        string(name: 'NODE_SELECTION_METHOD', defaultValue: 'QV_QUERY', description: 'Method to select target nodes: QV_QUERY or NODE_LIST.'),
                        string(name: 'OLD_DC_QV_QUERY', defaultValue: '-r role_cassandra_pfpt -d us-east-1', description: 'QV query for the OLD datacenter.'),
                        string(name: 'NEW_DC_QV_QUERY', defaultValue: '-r role_cassandra_pfpt -d eu-west-1', description: 'QV query for the NEW datacenter.'),
                        string(name: 'OLD_DC_NODES', defaultValue: '', description: 'Comma-separated list of nodes for the OLD datacenter.'),
                        string(name: 'NEW_DC_NODES', defaultValue: '', description: 'Comma-separated list of nodes for the NEW datacenter.'),
                        string(name: 'OLD_DC_NAME', defaultValue: 'us-east-1', description: 'The Cassandra name for the OLD datacenter.'),
                        string(name: 'NEW_DC_NAME', defaultValue: 'eu-west-1', description: 'The Cassandra name for the NEW datacenter.')
                    ])
                ])
                pipeline {
                    agent any
                    environment {
                        SCRIPTS_PATH = '/Users/ggonda/cassandra-tools/scripts'
                        PATH = "/opt/homebrew/bin:/usr/local/bin:${env.PATH}"
                    }
                    stages {
                        stage('Join Datacenters') {
                            steps {
                                script {
                                    def joinCommand = "${env.SCRIPTS_PATH}/join-cassandra-dcs.sh"
                                    if (params.NODE_SELECTION_METHOD == 'QV_QUERY') {
                                        joinCommand += " --old-dc-query \\"${params.OLD_DC_QV_QUERY}\\""
                                        joinCommand += " --new-dc-query \\"${params.NEW_DC_QV_QUERY}\\""
                                    } else {
                                        joinCommand += " --old-dc-nodes \\"${params.OLD_DC_NODES}\\""
                                        joinCommand += " --new-dc-nodes \\"${params.NEW_DC_NODES}\\""
                                    }
                                    joinCommand += " --old-dc-name ${params.OLD_DC_NAME}"
                                    joinCommand += " --new-dc-name ${params.NEW_DC_NAME}"
                                    sh joinCommand
                                }
                            }
                        }
                    }
                }
            '''.stripIndent())
            sandbox()
        }
    }
}

// =============================================================================
//  Split Datacenters Job
// =============================================================================
pipelineJob('Cassandra/Split') {
    description('Orchestrates splitting a multi-DC cluster into two independent clusters.')
    definition {
        cps {
            script('''
                properties([
                    parameters([
                        string(name: 'OPERATION', defaultValue: 'SPLIT_DCS', description: 'Selected operation (fixed for this job).'),
                        string(name: 'NODE_SELECTION_METHOD', defaultValue: 'QV_QUERY', description: 'Method to select target nodes: QV_QUERY or NODE_LIST.'),
                        string(name: 'DC1_QV_QUERY', defaultValue: '-r role_cassandra_pfpt -d us-east-1', description: 'QV query for the first datacenter.'),
                        string(name: 'DC2_QV_QUERY', defaultValue: '-r role_cassandra_pfpt -d eu-west-1', description: 'QV query for the second datacenter.'),
                        string(name: 'DC1_NODES', defaultValue: '', description: 'Comma-separated list of nodes for the first datacenter.'),
                        string(name: 'DC2_NODES', defaultValue: '', description: 'Comma-separated list of nodes for the second datacenter.'),
                        string(name: 'DC1_NAME', defaultValue: 'us-east-1', description: 'The Cassandra name for the first datacenter.'),
                        string(name: 'DC2_NAME', defaultValue: 'eu-west-1', description: 'The Cassandra name for the second datacenter.')
                    ])
                ])
                pipeline {
                    agent any
                    environment {
                        SCRIPTS_PATH = '/Users/ggonda/cassandra-tools/scripts'
                        PATH = "/opt/homebrew/bin:/usr/local/bin:${env.PATH}"
                    }
                    stages {
                        stage('Split Datacenters') {
                            steps {
                                script {
                                    def splitCommand = "${env.SCRIPTS_PATH}/split-cassandra-dcs.sh"
                                    if (params.NODE_SELECTION_METHOD == 'QV_QUERY') {
                                        splitCommand += " --dc1-query \\"${params.DC1_QV_QUERY}\\""
                                        splitCommand += " --dc2-query \\"${params.DC2_QV_QUERY}\\""
                                    } else {
                                        splitCommand += " --dc1-nodes \\"${params.DC1_NODES}\\""
                                        splitCommand += " --dc2-nodes \\"${params.DC2_NODES}\\""
                                    }
                                    splitCommand += " --dc1-name ${params.DC1_NAME}"
                                    splitCommand += " --dc2-name ${params.DC2_NAME}"
                                    sh splitCommand
                                }
                            }
                        }
                    }
                }
            '''.stripIndent())
            sandbox()
        }
    }
}

// =============================================================================
//  Rename Cluster Job
// =============================================================================
pipelineJob('Cassandra/Rename') {
    description('Orchestrates renaming an entire Cassandra cluster (requires downtime).')
    definition {
        cps {
            script('''
                properties([
                    parameters([
                        string(name: 'OPERATION', defaultValue: 'RENAME_CLUSTER', description: 'Selected operation (fixed for this job).'),
                        string(name: 'NODE_SELECTION_METHOD', defaultValue: 'QV_QUERY', description: 'Method to select target nodes: QV_QUERY or NODE_LIST.'),
                        string(name: 'QV_QUERY', defaultValue: '-r role_cassandra_pfpt', description: 'QV query for all nodes in the cluster.'),
                        string(name: 'NODE_LIST', defaultValue: '', description: 'Comma-separated list of all nodes in the cluster.'),
                        string(name: 'OLD_NAME', defaultValue: 'MyProductionCluster', description: 'The current cluster name.'),
                        string(name: 'NEW_NAME', defaultValue: 'MyPrimaryCluster', description: 'The new cluster name.')
                    ])
                ])
                pipeline {
                    agent any
                    environment {
                        SCRIPTS_PATH = '/Users/ggonda/cassandra-tools/scripts'
                        PATH = "/opt/homebrew/bin:/usr/local/bin:${env.PATH}"
                    }
                    stages {
                        stage('Rename Cluster') {
                            steps {
                                script {
                                    def renameCommand = "${env.SCRIPTS_PATH}/rename-cassandra-cluster.sh"
                                    if (params.NODE_SELECTION_METHOD == 'QV_QUERY') {
                                        renameCommand += " --qv-query \\"${params.QV_QUERY}\\""
                                    } else {
                                        renameCommand += " --nodes \\"${params.NODE_LIST}\\""
                                    }
                                    renameCommand += " --old-name ${params.OLD_NAME}"
                                    renameCommand += " --new-name ${params.NEW_NAME}"
                                    sh renameCommand
                                }
                            }
                        }
                    }
                }
            '''.stripIndent())
            sandbox()
        }
    }
}

// =============================================================================
//  Rolling Restart Job
// =============================================================================
pipelineJob('Cassandra/Restart') {
    description('Performs a safe, rolling restart of Cassandra nodes.')
    definition {
        cps {
            script('''
                properties([
                    parameters([
                        string(name: 'OPERATION', defaultValue: 'ROLLING_RESTART', description: 'Selected operation (fixed for this job).'),
                        string(name: 'NODE_SELECTION_METHOD', defaultValue: 'QV_QUERY', description: 'Method to select target nodes: QV_QUERY or NODE_LIST.'),
                        string(name: 'QV_QUERY', defaultValue: '-r role_cassandra_pfpt -d AWSLAB', description: 'QV query for the target datacenter.'),
                        string(name: 'NODE_LIST', defaultValue: '', description: 'A comma-separated list of nodes to restart.')
                    ])
                ])
                pipeline {
                    agent any
                    environment {
                        SCRIPTS_PATH = '/Users/ggonda/cassandra-tools/scripts'
                        PATH = "/opt/homebrew/bin:/usr/local/bin:${env.PATH}"
                    }
                    stages {
                        stage('Rolling Restart') {
                            steps {
                                script {
                                    def cassyCommand = "${env.SCRIPTS_PATH}/cassy.sh --rolling-op restart"
                                    if (params.NODE_SELECTION_METHOD == 'QV_QUERY') {
                                        cassyCommand += " --qv-query \\"${params.QV_QUERY}\\""
                                    } else {
                                        cassyCommand += " --nodes \\"${params.NODE_LIST}\\""
                                    }
                                    sh cassyCommand
                                }
                            }
                        }
                    }
                }
            '''.stripIndent())
            sandbox()
        }
    }
}

// =============================================================================
//  Rolling Reboot Job
// =============================================================================
pipelineJob('Cassandra/Reboot') {
    description('Performs a safe, rolling reboot of Cassandra nodes.')
    definition {
        cps {
            script('''
                properties([
                    parameters([
                        string(name: 'OPERATION', defaultValue: 'ROLLING_REBOOT', description: 'Selected operation (fixed for this job).'),
                        string(name: 'NODE_SELECTION_METHOD', defaultValue: 'QV_QUERY', description: 'Method to select target nodes: QV_QUERY or NODE_LIST.'),
                        string(name: 'QV_QUERY', defaultValue: '-r role_cassandra_pfpt -d AWSLAB', description: 'QV query for the target datacenter.'),
                        string(name: 'NODE_LIST', defaultValue: '', description: 'A comma-separated list of nodes to reboot.')
                    ])
                ])
                pipeline {
                    agent any
                    environment {
                        SCRIPTS_PATH = '/Users/ggonda/cassandra-tools/scripts'
                        PATH = "/opt/homebrew/bin:/usr/local/bin:${env.PATH}"
                    }
                    stages {
                        stage('Rolling Reboot') {
                            steps {
                                script {
                                    def cassyCommand = "${env.SCRIPTS_PATH}/cassy.sh --rolling-op reboot"
                                    if (params.NODE_SELECTION_METHOD == 'QV_QUERY') {
                                        cassyCommand += " --qv-query \\"${params.QV_QUERY}\\""
                                    } else {
                                        cassyCommand += " --nodes \\"${params.NODE_LIST}\\""
                                    }
                                    sh cassyCommand
                                }
                            }
                        }
                    }
                }
            '''.stripIndent())
            sandbox()
        }
    }
}

// =============================================================================
//  Rolling Puppet Run Job
// =============================================================================
pipelineJob('Cassandra/Puppet-Run') {
    description('Performs a safe, rolling Puppet run on Cassandra nodes.')
    definition {
        cps {
            script('''
                properties([
                    parameters([
                        string(name: 'OPERATION', defaultValue: 'ROLLING_PUPPET_RUN', description: 'Selected operation (fixed for this job).'),
                        string(name: 'NODE_SELECTION_METHOD', defaultValue: 'QV_QUERY', description: 'Method to select target nodes: QV_QUERY or NODE_LIST.'),
                        string(name: 'QV_QUERY', defaultValue: '-r role_cassandra_pfpt -d AWSLAB', description: 'QV query for the target datacenter.'),
                        string(name: 'NODE_LIST', defaultValue: '', description: 'A comma-separated list of nodes to run Puppet on.')
                    ])
                ])
                pipeline {
                    agent any
                    environment {
                        SCRIPTS_PATH = '/Users/ggonda/cassandra-tools/scripts'
                        PATH = "/opt/homebrew/bin:/usr/local/bin:${env.PATH}"
                    }
                    stages {
                        stage('Rolling Puppet Run') {
                            steps {
                                script {
                                    def cassyCommand = "${env.SCRIPTS_PATH}/cassy.sh --rolling-op puppet"
                                    if (params.NODE_SELECTION_METHOD == 'QV_QUERY') {
                                        cassyCommand += " --qv-query \\"${params.QV_QUERY}\\""
                                    } else {
                                        cassyCommand += " --nodes \\"${params.NODE_LIST}\\""
                                    }
                                    sh cassyCommand
                                }
                            }
                        }
                    }
                }
            '''.stripIndent())
            sandbox()
        }
    }
}

// =============================================================================
//  Compaction Job
// =============================================================================
pipelineJob('Cassandra/Compaction') {
    description('Runs `nodetool compact` on a set of nodes with various scopes.')
    definition {
        cps {
            script('''
                properties([
                    parameters([
                        choice(name: 'TARGET_METHOD', choices: ['QV_QUERY', 'NODE_LIST'], description: 'Method to select target nodes.'),
                        string(name: 'QV_QUERY', defaultValue: '-r role_cassandra_pfpt', description: 'QV query for target nodes (if method is QV_QUERY).'),
                        string(name: 'NODE_LIST', defaultValue: '', description: 'Comma-separated list of nodes (if method is NODE_LIST).'),
                        
                        choice(name: 'SCOPE', choices: ['ENTIRE_NODE', 'KEYSPACE', 'TABLES'], description: 'Compaction scope.'),
                        string(name: 'KEYSPACE', defaultValue: '', description: 'Keyspace name (required for KEYSPACE and TABLES scope).'),
                        string(name: 'TABLES', defaultValue: '', description: 'Comma-separated list of tables (for TABLES scope).'),
                        
                        string(name: 'JOBS', defaultValue: '0', description: 'Number of concurrent compaction jobs (0 for auto).'),
                        booleanParam(name: 'PARALLEL_EXECUTION', defaultValue: false, description: 'Run cassy.sh in parallel on target nodes? DANGEROUS for compaction.')
                    ])
                ])

                pipeline {
                    agent any
                    environment {
                        SCRIPTS_PATH = '/Users/ggonda/cassandra-tools/scripts'
                        PATH = "/opt/homebrew/bin:/usr/local/bin:${env.PATH}"
                    }
                    stages {
                        stage('Run Compaction') {
                            steps {
                                script {
                                    def cassyCommand = "${env.SCRIPTS_PATH}/cassy.sh"
                                    if (params.TARGET_METHOD == 'QV_QUERY') {
                                        cassyCommand += " --qv-query \\"${params.QV_QUERY}\\""
                                    } else {
                                        cassyCommand += " --nodes \\"${params.NODE_LIST}\\""
                                    }

                                    if (params.PARALLEL_EXECUTION) {
                                        cassyCommand += ' --parallel'
                                    }

                                    def opsCommand = "sudo /usr/local/bin/cass-ops compact -j ${params.JOBS}"
                                    if (params.SCOPE == 'KEYSPACE') {
                                        if (params.KEYSPACE.trim().isEmpty()) { error("KEYSPACE must be provided for KEYSPACE scope.") }
                                        opsCommand += " -k ${params.KEYSPACE}"
                                    } else if (params.SCOPE == 'TABLES') {
                                        if (params.KEYSPACE.trim().isEmpty() || params.TABLES.trim().isEmpty()) { error("KEYSPACE and TABLES must be provided for TABLES scope.") }
                                        def tableFlags = params.TABLES.split(',').collect { "-t ${it.trim()}" }.join(' ')
                                        opsCommand += " -k ${params.KEYSPACE} ${tableFlags}"
                                    }
                                    
                                    cassyCommand += " -c '${opsCommand}'"
                                    sh cassyCommand
                                }
                            }
                        }
                    }
                }
            '''.stripIndent())
            sandbox()
        }
    }
}

// =============================================================================
//  Garbage Collect Job
// =============================================================================
pipelineJob('Cassandra/Garbage-Collect') {
    description('Runs `nodetool garbagecollect` on a set of nodes with various scopes.')
    definition {
        cps {
            script('''
                properties([
                    parameters([
                        choice(name: 'TARGET_METHOD', choices: ['QV_QUERY', 'NODE_LIST'], description: 'Method to select target nodes.'),
                        string(name: 'QV_QUERY', defaultValue: '-r role_cassandra_pfpt', description: 'QV query for target nodes (if method is QV_QUERY).'),
                        string(name: 'NODE_LIST', defaultValue: '', description: 'Comma-separated list of nodes (if method is NODE_LIST).'),
                        
                        choice(name: 'SCOPE', choices: ['ENTIRE_NODE', 'KEYSPACE', 'TABLES'], description: 'Garbage collection scope.'),
                        string(name: 'KEYSPACE', defaultValue: '', description: 'Keyspace name (required for KEYSPACE and TABLES scope).'),
                        string(name: 'TABLES', defaultValue: '', description: 'Comma-separated list of tables (for TABLES scope).'),
                        
                        choice(name: 'GRANULARITY', choices: ['ROW', 'CELL'], description: 'Granularity of tombstones to remove.'),
                        string(name: 'JOBS', defaultValue: '0', description: 'Number of concurrent GC jobs (0 for auto).'),
                        booleanParam(name: 'PARALLEL_EXECUTION', defaultValue: false, description: 'Run cassy.sh in parallel on target nodes? DANGEROUS for garbage collection.')
                    ])
                ])

                pipeline {
                    agent any
                    environment {
                        SCRIPTS_PATH = '/Users/ggonda/cassandra-tools/scripts'
                        PATH = "/opt/homebrew/bin:/usr/local/bin:${env.PATH}"
                    }
                    stages {
                        stage('Run Garbage Collect') {
                            steps {
                                script {
                                    def cassyCommand = "${env.SCRIPTS_PATH}/cassy.sh"
                                    if (params.TARGET_METHOD == 'QV_QUERY') {
                                        cassyCommand += " --qv-query \\"${params.QV_QUERY}\\""
                                    } else {
                                        cassyCommand += " --nodes \\"${params.NODE_LIST}\\""
                                    }

                                    if (params.PARALLEL_EXECUTION) {
                                        cassyCommand += ' --parallel'
                                    }
                                    
                                    def opsCommand = "sudo /usr/local/bin/cass-ops garbage-collect -g ${params.GRANULARITY} -j ${params.JOBS}"
                                    if (params.SCOPE == 'KEYSPACE') {
                                        if (params.KEYSPACE.trim().isEmpty()) { error("KEYSPACE must be provided for KEYSPACE scope.") }
                                        opsCommand += " -k ${params.KEYSPACE}"
                                    } else if (params.SCOPE == 'TABLES') {
                                        if (params.KEYSPACE.trim().isEmpty() || params.TABLES.trim().isEmpty()) { error("KEYSPACE and TABLES must be provided for TABLES scope.") }
                                        def tableFlags = params.TABLES.split(',').collect { "-t ${it.trim()}" }.join(' ')
                                        opsCommand += " -k ${params.KEYSPACE} ${tableFlags}"
                                    }
                                    
                                    cassyCommand += " -c '${opsCommand}'"
                                    sh cassyCommand
                                }
                            }
                        }
                    }
                }
            '''.stripIndent())
            sandbox()
        }
    }
}
