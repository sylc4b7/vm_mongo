#!/bin/bash

# Create Lambda deployment package with API Gateway support
zip lambda_function.zip lambda_function_api.py

# Create pymongo layer
mkdir -p python
pip install pymongo -t python/
zip -r pymongo-layer.zip python/
rm -rf python/

# Deploy Phase 3 with API Gateway
cp main-api.tf main.tf
cp outputs-api.tf outputs.tf

# Deploy with Terraform
terraform init
terraform plan
terraform apply -auto-approve

echo "=== API Gateway Deployed ==="
echo "API URL: $(terraform output -raw api_gateway_invoke_url)"
echo ""
echo "Test with curl:"
echo "curl -X POST $(terraform output -raw api_gateway_invoke_url) \\"
echo "  -H 'Content-Type: application/json' \\"
echo "  -d '{\"action\":\"insert\",\"data\":{\"name\":\"test\",\"value\":123}}'"