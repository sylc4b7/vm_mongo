#!/bin/bash

# Generate SSH key if it doesn't exist
if [ ! -f ~/.ssh/id_rsa ]; then
    ssh-keygen -t rsa -b 2048 -f ~/.ssh/id_rsa -N ""
fi

# Create Lambda deployment package
zip lambda_function.zip lambda_function.py

# Create pymongo layer
mkdir -p python
pip install pymongo -t python/
zip -r pymongo-layer.zip python/
rm -rf python/

# Deploy with Terraform
terraform init
terraform plan
terraform apply -auto-approve