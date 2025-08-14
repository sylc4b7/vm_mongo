#!/bin/bash

echo "=== MongoDB Lambda AWS - Phase 1 Test Script ==="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test function
test_result() {
    if [ $1 -eq 0 ]; then
        echo -e "${GREEN}✅ PASS${NC}: $2"
    else
        echo -e "${RED}❌ FAIL${NC}: $2"
    fi
}

echo -e "${YELLOW}=== PHASE 1: PUBLIC SETUP TESTS ===${NC}"

echo "1. Testing Terraform outputs..."
PUBLIC_IP=$(terraform output -raw ec2_public_ip 2>/dev/null)
PRIVATE_IP=$(terraform output -raw ec2_private_ip 2>/dev/null)
LAMBDA_NAME=$(terraform output -raw lambda_function_name 2>/dev/null)

test_result $? "Terraform outputs available"
echo "   Public IP: $PUBLIC_IP"
echo "   Private IP: $PRIVATE_IP"
echo "   Lambda: $LAMBDA_NAME"

echo ""
echo "2. Testing SSH connectivity..."
timeout 10 ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -i ~/.ssh/id_rsa ubuntu@$PUBLIC_IP "echo 'SSH works'" 2>/dev/null
test_result $? "SSH access to EC2"

echo ""
echo "3. Testing MongoDB on EC2..."
timeout 10 ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -i ~/.ssh/id_rsa ubuntu@$PUBLIC_IP "sudo systemctl is-active mongod" 2>/dev/null | grep -q "active"
test_result $? "MongoDB service running"

echo ""
echo "4. Testing Lambda function..."
aws lambda invoke --function-name $LAMBDA_NAME --payload $(echo '{"action":"insert","data":{"test":"phase1","value":123}}' | base64 -w 0) response.json >/dev/null 2>&1
grep -q "inserted_id" response.json
test_result $? "Lambda insert operation"

aws lambda invoke --function-name $LAMBDA_NAME --payload $(echo '{"action":"find","query":{"test":"phase1"}}' | base64 -w 0) response.json >/dev/null 2>&1
grep -q "phase1" response.json
test_result $? "Lambda find operation"

echo ""
echo -e "${YELLOW}=== PHASE 1 COMPLETE ===${NC}"
echo "To view inserted data:"
echo "aws lambda invoke --function-name $LAMBDA_NAME --payload '{\"action\":\"find\",\"query\":{}}' response.json && cat response.json"

# Cleanup
rm -f response.json