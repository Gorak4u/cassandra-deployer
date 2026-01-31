// This file is managed by Puppet.
// This Groovy script uses the Jenkins Job DSL plugin to automatically generate pipeline jobs.

// Define all the operations. The 'operation' key corresponds to the Jenkinsfile name suffix.
def jobs = [
    [operation: 'generic_command',      description: 'Run any ad-hoc cass-ops command against a set of nodes.'],
    [operation: 'join_dcs',             description: 'Orchestrates joining a new datacenter to an existing Cassandra cluster.'],
    [operation: 'rename_cluster',       description: 'Orchestrates a full cluster rename. REQUIRES DOWNTIME.'],
    [operation: 'rolling_puppet_run',   description: 'Performs a safe, rolling Puppet agent run across the cluster.'],
    [operation: 'rolling_reboot',       description: 'Performs a safe, rolling reboot of the cluster nodes.'],
    [operation: 'rolling_restart',      description: 'Performs a safe, rolling restart of the Cassandra service.'],
    [operation: 'split_dcs',            description: 'Orchestrates splitting a multi-DC cluster into two independent clusters.']
]

// Loop through the definitions and create a pipeline job for each one.
jobs.each { jobInfo ->
    // Sanitize the operation name to create a clean job name, e.g., 'rolling_restart' -> 'Cassandra-Rolling-Restart'
    def jobName = "Cassandra-${jobInfo.operation.replaceAll('_', ' ').capitalize().replaceAll(' ', '-')}"
    def jenkinsfilePath = "jenkins/Jenkinsfile.${jobInfo.operation}"

    pipelineJob(jobName) {
        description(jobInfo.description)
        
        // This tells the job to use the content of the specified Jenkinsfile as its pipeline script.
        definition {
            cps {
                // readFileFromWorkspace is a DSL function that reads a file from the job's workspace.
                script(readFileFromWorkspace(jenkinsfilePath))
                // The sandbox ensures the script runs in a secure environment.
                sandbox(true)
            }
        }
    }
}
