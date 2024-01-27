#!/bin/bash
# shellcheck disable=SC2002

TF_VAR_project_name=desafio-devops
TF_VAR_aws_region=us-east-1
TF_VAR_aws_profile=jenkins
TF_VAR_image_build_number=${BUILD_NUMBER}
TF_VAR_untagged_images=3
TF_VAR_domain_name="bluesoft.com.br"
TF_VAR_aws_public_key="<CHAVE PUB>"

export TF_VAR_project_name
export TF_VAR_aws_region
export TF_VAR_aws_profile
export TF_VAR_image_build_number
export TF_VAR_untagged_images
export TF_VAR_aws_public_key
export TF_VAR_domain_name