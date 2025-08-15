#!/bin/bash

# Generate SSH key if it doesn't exist
if [ ! -f ~/.ssh/id_rsa ]; then
    ssh-keygen -t rsa -b 2048 -f ~/.ssh/id_rsa -N ""
fi

# Create Lambda deployment package
zip lambda_function.zip lambda_function.py

# Create pymongo layer
mkdir -p python
# Use virtual environment to avoid externally managed environment error
python3 -m venv temp_venv
temp_venv/bin/pip install pymongo -t python/
zip -r pymongo-layer.zip python/
rm -rf python/ temp_venv/

# Deploy with Terraform
terraform init
terraform plan
terraform apply -auto-approve