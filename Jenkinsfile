#!groovy
pipeline {
  environment {
    TF_VAR_image_build_number = "${BUILD_NUMBER}"
    TF_VAR_project_name="desafio-devops"
    TF_VAR_aws_region="us-east-1"
    TF_VAR_aws_profile="default"
    TF_VAR_untagged_images="3"
    TF_VAR_domain_name="bluesoft.com.br"
    TF_VAR_aws_public_key="<CHAVE PUB>"
    projectName = "${TF_VAR_project_name}"
  }
  agent any
  stages {
    stage('Git Pull'){
      steps{
        git branch: 'main', url: 'https://github.com/bluesoft/desafio-devops-java-app.git'
      }
    }
    stage('Docker Build') {
      steps {
    	  sh 'docker image build -t ${projectName}:${BUILD_NUMBER} .'
      }
    }
    stage('Terraform init'){
      steps{
          sh 'terraform init --upgrade'
        }
    }
    stage('Terraform plan'){
      steps{
        withAWS(credentials: 'AWSID'){
          sh 'terraform plan'
        }
      }
    }
    stage('Terraform apply'){
      steps{
        withAWS(credentials: 'AWSID'){
          sh 'terraform apply --auto-approve'
        }
      }
    }
  }
}
