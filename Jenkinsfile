pipeline {
    agent any

    environment {
        ELK_STACK_VERSION = "7.14.0"  // Укажите нужную версию ELK Stack
    }

    stages {
        stage('Checkout') {
            steps {
                // Проверка исходного кода из вашего репозитория (если используется)
                checkout scm
            }
        }

        stage('Setup ELK Stack') {
            steps {
                script {
                    // Развертывание Elasticsearch
                    sh '''
                    docker pull docker.elastic.co/elasticsearch/elasticsearch:${ELK_STACK_VERSION}
                    docker run -d --name elasticsearch -p 9200:9200 -p 9300:9300 \
                        -e "discovery.type=single-node" \
                        docker.elastic.co/elasticsearch/elasticsearch:${ELK_STACK_VERSION}
                    '''

                    // Развертывание Logstash
                    sh '''
                    docker pull docker.elastic.co/logstash/logstash:${ELK_STACK_VERSION}
                    docker run -d --name logstash -p 5044:5044 -p 9600:9600 \
                        -v $WORKSPACE/logstash.conf:/usr/share/logstash/pipeline/logstash.conf \
                        docker.elastic.co/logstash/logstash:${ELK_STACK_VERSION}
                    '''

                    // Развертывание Kibana
                    sh '''
                    docker pull docker.elastic.co/kibana/kibana:${ELK_STACK_VERSION}
                    docker run -d --name kibana -p 5601:5601 \
                        -e "ELASTICSEARCH_HOSTS=http://elasticsearch:9200" \
                        docker.elastic.co/kibana/kibana:${ELK_STACK_VERSION}
                    '''
                }
            }
        }

        stage('Verify ELK Stack') {
            steps {
                script {
                    // Проверка доступности Elasticsearch
                    sh 'curl -X GET "localhost:9200"'

                    // Проверка доступности Kibana
                    sh 'curl -X GET "localhost:5601"'
                }
            }
        }
    }

    post {
        always {
            // Удаление контейнеров после завершения сборки
            sh '''
            docker stop elasticsearch logstash kibana
            docker rm elasticsearch logstash kibana
            '''
        }
    }
}
