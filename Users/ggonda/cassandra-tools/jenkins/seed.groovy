// This seed job script discovers all 'Jenkinsfile.*' files in its directory
// and creates a corresponding Jenkins pipeline job for each one.
// It is designed to be run by the Jenkins Job DSL plugin.

// Define the absolute path to the directory containing the Jenkinsfiles on the Jenkins agent.
def jenkinsDir = new File('/Users/ggonda/cassandra-tools/jenkins')

if (!jenkinsDir.exists() || !jenkinsDir.isDirectory()) {
    error("ERROR: The Jenkinsfile directory was not found at ${jenkinsDir.absolutePath}. Please ensure the directory exists on the Jenkins agent.")
    return
}

// Find all files matching the Jenkinsfile.* pattern in the specified directory.
def jenkinsfiles = []
jenkinsDir.eachFileMatch(~/Jenkinsfile\..+/) { file ->
    jenkinsfiles << file
}

if (jenkinsfiles.isEmpty()) {
    println "No Jenkinsfiles found in ${jenkinsDir.absolutePath}. No jobs will be created."
    return
}

// Iterate over each discovered Jenkinsfile and create a pipeline job.
jenkinsfiles.each { jenkinsfile ->
    // Extract the operation name from the filename (e.g., 'Jenkinsfile.restart' -> 'restart').
    def operation = jenkinsfile.name.split('\\.')[1]
    def jobName = "Cassandra - ${operation.capitalize()}"

    println "Creating/Updating job: ${jobName}"

    pipelineJob(jobName) {
        description("Runs the '${operation}' operation on the Cassandra cluster.")

        // Use the content of the Jenkinsfile as the pipeline script.
        definition {
            cps {
                script(jenkinsfile.text)
                sandbox() // Run the pipeline script in a sandbox for security.
            }
        }
    }
}
