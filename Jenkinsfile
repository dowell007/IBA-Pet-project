pipeline {
    agent any
    
    stages {
        stage('Setup ELK Stack') {
            steps {
                script {
                    sh 'docker pull docker.elastic.co/elasticsearch/elasticsearch:7.14.0'
                }
            }
        }
        
        stage('Verify ELK Stack') {
            steps {
                script {
                    // Ваши команды для проверки ELK Stack
                }
            }
        }
    }
    
    post {
        always {
            script {
                sh 'docker stop elasticsearch logstash kibana'
            }
        }
    }
}

