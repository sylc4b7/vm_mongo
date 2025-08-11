#!/bin/bash

echo "=== MongoDB Lambda AWS - All Phases Test Script ==="
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

# Phase 1 Tests
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
aws lambda invoke --function-name $LAMBDA_NAME --payload '{"action":"insert","data":{"test":"phase1","timestamp":"'$(date)'"}}' response.json >/dev/null 2>&1
grep -q "200" response.json
test_result $? "Lambda insert operation"

aws lambda invoke --function-name $LAMBDA_NAME --payload '{"action":"find","query":{"test":"phase1"}}' response.json >/dev/null 2>&1
grep -q "phase1" response.json
test_result $? "Lambda find operation"

echo ""
echo -e "${YELLOW}=== PHASE 2: PRIVATE SETUP TESTS ===${NC}"

echo "1. Testing private configuration..."
# Check if public IP is removed (this would be after switching to private config)
PRIVATE_IP=$(terraform output -raw ec2_private_ip 2>/dev/null)
echo "   Private IP: $PRIVATE_IP"

echo ""
echo "2. Testing Lambda still works in private mode..."
aws lambda invoke --function-name $LAMBDA_NAME --payload '{"action":"insert","data":{"test":"phase2","secure":true}}' response.json >/dev/null 2>&1
grep -q "200" response.json
test_result $? "Lambda works in private mode"

echo ""
echo -e "${YELLOW}=== PHASE 3: API GATEWAY TESTS ===${NC}"

echo "1. Testing API Gateway endpoint..."
API_URL=$(terraform output -raw api_gateway_invoke_url 2>/dev/null)
echo "   API URL: $API_URL"

if [ ! -z "$API_URL" ]; then
    echo ""
    echo "2. Testing API Gateway INSERT..."
    RESPONSE=$(curl -s -X POST $API_URL \
        -H 'Content-Type: application/json' \
        -d '{"action":"insert","data":{"test":"phase3","method":"curl","timestamp":"'$(date)'"}}')
    echo "$RESPONSE" | grep -q "inserted_id"
    test_result $? "API Gateway INSERT via curl"

    echo ""
    echo "3. Testing API Gateway FIND..."
    RESPONSE=$(curl -s -X POST $API_URL \
        -H 'Content-Type: application/json' \
        -d '{"action":"find","query":{"test":"phase3"}}')
    echo "$RESPONSE" | grep -q "phase3"
    test_result $? "API Gateway FIND via curl"

    echo ""
    echo "4. Testing API Gateway UPDATE..."
    RESPONSE=$(curl -s -X POST $API_URL \
        -H 'Content-Type: application/json' \
        -d '{"action":"update","query":{"test":"phase3"},"update":{"$set":{"updated":true}}}')
    echo "$RESPONSE" | grep -q "modified_count"
    test_result $? "API Gateway UPDATE via curl"

    echo ""
    echo "5. Testing API Gateway DELETE..."
    RESPONSE=$(curl -s -X POST $API_URL \
        -H 'Content-Type: application/json' \
        -d '{"action":"delete","query":{"test":"phase3"}}')
    echo "$RESPONSE" | grep -q "deleted_count"
    test_result $? "API Gateway DELETE via curl"

    echo ""
    echo "6. Testing CORS headers..."
    CORS_HEADERS=$(curl -s -X OPTIONS $API_URL -I | grep -i "access-control")
    if [ ! -z "$CORS_HEADERS" ]; then
        test_result 0 "CORS headers present"
        echo "   $CORS_HEADERS"
    else
        test_result 1 "CORS headers present"
    fi
else
    echo "   API Gateway not deployed - skipping tests"
fi

echo ""
echo -e "${YELLOW}=== SUMMARY ===${NC}"
echo "Test completed. Check individual results above."
echo ""
echo "To view all data in MongoDB:"
if [ ! -z "$API_URL" ]; then
    echo "curl -X POST $API_URL -H 'Content-Type: application/json' -d '{\"action\":\"find\",\"query\":{}}'"
else
    echo "aws lambda invoke --function-name $LAMBDA_NAME --payload '{\"action\":\"find\",\"query\":{}}' response.json && cat response.json"
fi

echo ""
echo "To clean up all resources:"
echo "terraform destroy -auto-approve"

# Cleanup
rm -f response.json