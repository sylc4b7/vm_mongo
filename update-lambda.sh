#!/bin/bash

echo "=== Lambda Code Update Workflow ==="
echo ""

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Step 1: Edit lambda_function.py${NC}"
echo "   (Manual step - edit your code)"
echo ""

echo -e "${YELLOW}Step 2: Repackage Lambda function${NC}"
echo "   Removing old package..."
rm -f lambda_function.zip

echo "   Creating new package..."
zip lambda_function.zip lambda_function.py
echo -e "${GREEN}   ✅ Lambda function repackaged${NC}"
echo ""

echo -e "${YELLOW}Step 3: Deploy with Terraform${NC}"
echo "   Checking for changes..."
terraform plan

echo ""
read -p "Apply changes? (y/N): " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "   Deploying changes..."
    terraform apply -auto-approve
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ Lambda function updated successfully!${NC}"
        echo ""
        echo "Testing the updated function..."
        API_BASE_URL=$(terraform output -raw api_gateway_base_url 2>/dev/null)
        if [ ! -z "$API_BASE_URL" ]; then
            curl -X GET "$API_BASE_URL/api/health"
        fi
    else
        echo "❌ Deployment failed"
        exit 1
    fi
else
    echo "Deployment cancelled."
fi

echo ""
echo -e "${GREEN}Lambda update workflow completed!${NC}"