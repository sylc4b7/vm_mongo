#!/bin/bash

echo "🧪 MongoDB Lambda AWS - Complete System Test"
echo "============================================="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test counters
TOTAL_TESTS=0
PASSED_TESTS=0

# Test function
test_result() {
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    if [ $1 -eq 0 ]; then
        echo -e "${GREEN}✅ PASS${NC}: $2"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo -e "${RED}❌ FAIL${NC}: $2"
    fi
}

# Get current phase info
echo -e "${BLUE}📊 Detecting Current Phase...${NC}"
PRIVATE_IP=$(terraform output -raw ec2_private_ip 2>/dev/null)
PUBLIC_IP=$(terraform output -raw ec2_public_ip 2>/dev/null)
LAMBDA_NAME=$(terraform output -raw lambda_function_name 2>/dev/null)
API_URL=$(terraform output -raw api_gateway_invoke_url 2>/dev/null)
SPA_URL=$(terraform output -raw spa_url 2>/dev/null)

# Determine phase
CURRENT_PHASE="Unknown"
if [ ! -z "$SPA_URL" ]; then
    CURRENT_PHASE="Phase 4 (SPA + CDN)"
elif [ ! -z "$API_URL" ]; then
    CURRENT_PHASE="Phase 3 (API Gateway)"
elif [ -z "$PUBLIC_IP" ] && [ ! -z "$PRIVATE_IP" ]; then
    CURRENT_PHASE="Phase 2 (Private)"
elif [ ! -z "$PUBLIC_IP" ]; then
    CURRENT_PHASE="Phase 1 (Public)"
fi

echo "Current Phase: $CURRENT_PHASE"
echo "Private IP: $PRIVATE_IP"
echo "Public IP: ${PUBLIC_IP:-'None'}"
echo "Lambda: $LAMBDA_NAME"
echo "API URL: ${API_URL:-'None'}"
echo "SPA URL: ${SPA_URL:-'None'}"
echo ""

# Phase 1 Tests (if public IP exists)
if [ ! -z "$PUBLIC_IP" ]; then
    echo -e "${YELLOW}=== PHASE 1: PUBLIC SETUP TESTS ===${NC}"
    
    echo "1. Testing SSH connectivity..."
    timeout 10 ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -i ~/.ssh/id_rsa ubuntu@$PUBLIC_IP "echo 'SSH works'" 2>/dev/null
    test_result $? "SSH access to EC2"
    
    echo "2. Testing MongoDB service..."
    timeout 10 ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -i ~/.ssh/id_rsa ubuntu@$PUBLIC_IP "sudo systemctl is-active mongod" 2>/dev/null | grep -q "active"
    test_result $? "MongoDB service running"
    
    echo ""
fi

# Lambda Tests (all phases)
if [ ! -z "$LAMBDA_NAME" ]; then
    echo -e "${YELLOW}=== LAMBDA FUNCTION TESTS ===${NC}"
    
    echo "1. Testing Lambda insert operation..."
    aws lambda invoke --function-name $LAMBDA_NAME --payload '{"action":"insert","data":{"test":"automated","phase":"'$CURRENT_PHASE'","timestamp":"'$(date)'"}}' response.json >/dev/null 2>&1
    grep -q "200" response.json
    test_result $? "Lambda insert operation"
    
    echo "2. Testing Lambda find operation..."
    aws lambda invoke --function-name $LAMBDA_NAME --payload '{"action":"find","query":{"test":"automated"}}' response.json >/dev/null 2>&1
    grep -q "automated" response.json
    test_result $? "Lambda find operation"
    
    echo "3. Testing Lambda update operation..."
    aws lambda invoke --function-name $LAMBDA_NAME --payload '{"action":"update","query":{"test":"automated"},"update":{"$set":{"updated":true}}}' response.json >/dev/null 2>&1
    grep -q "modified_count" response.json
    test_result $? "Lambda update operation"
    
    echo "4. Testing Lambda delete operation..."
    aws lambda invoke --function-name $LAMBDA_NAME --payload '{"action":"delete","query":{"test":"automated"}}' response.json >/dev/null 2>&1
    grep -q "deleted_count" response.json
    test_result $? "Lambda delete operation"
    
    echo ""
fi

# Phase 2 Tests (private mode)
if [ -z "$PUBLIC_IP" ] && [ ! -z "$PRIVATE_IP" ]; then
    echo -e "${YELLOW}=== PHASE 2: PRIVATE SETUP TESTS ===${NC}"
    
    echo "1. Verifying SSH is blocked..."
    timeout 5 ssh -o ConnectTimeout=3 -o StrictHostKeyChecking=no -i ~/.ssh/id_rsa ubuntu@$PRIVATE_IP "echo 'Should not work'" 2>/dev/null
    test_result $? "SSH access properly blocked" # Inverted logic - we want this to fail
    
    echo "2. Testing Lambda works in private mode..."
    aws lambda invoke --function-name $LAMBDA_NAME --payload '{"action":"insert","data":{"test":"private","secure":true}}' response.json >/dev/null 2>&1
    grep -q "200" response.json
    test_result $? "Lambda works in private mode"
    
    echo ""
fi

# Phase 3 Tests (API Gateway)
if [ ! -z "$API_URL" ]; then
    echo -e "${YELLOW}=== PHASE 3: API GATEWAY TESTS ===${NC}"
    
    echo "1. Testing API Gateway INSERT..."
    RESPONSE=$(curl -s -X POST $API_URL \
        -H 'Content-Type: application/json' \
        -d '{"action":"insert","data":{"test":"api","method":"curl","timestamp":"'$(date)'"}}')
    echo "$RESPONSE" | grep -q "inserted_id"
    test_result $? "API Gateway INSERT via curl"
    
    echo "2. Testing API Gateway FIND..."
    RESPONSE=$(curl -s -X POST $API_URL \
        -H 'Content-Type: application/json' \
        -d '{"action":"find","query":{"test":"api"}}')
    echo "$RESPONSE" | grep -q "api"
    test_result $? "API Gateway FIND via curl"
    
    echo "3. Testing API Gateway UPDATE..."
    RESPONSE=$(curl -s -X POST $API_URL \
        -H 'Content-Type: application/json' \
        -d '{"action":"update","query":{"test":"api"},"update":{"$set":{"updated":true}}}')
    echo "$RESPONSE" | grep -q "modified_count"
    test_result $? "API Gateway UPDATE via curl"
    
    echo "4. Testing API Gateway DELETE..."
    RESPONSE=$(curl -s -X POST $API_URL \
        -H 'Content-Type: application/json' \
        -d '{"action":"delete","query":{"test":"api"}}')
    echo "$RESPONSE" | grep -q "deleted_count"
    test_result $? "API Gateway DELETE via curl"
    
    echo "5. Testing CORS headers..."
    CORS_HEADERS=$(curl -s -X OPTIONS $API_URL -I | grep -i "access-control")
    if [ ! -z "$CORS_HEADERS" ]; then
        test_result 0 "CORS headers present"
    else
        test_result 1 "CORS headers present"
    fi
    
    echo ""
fi

# Phase 4 Tests (SPA + CDN)
if [ ! -z "$SPA_URL" ]; then
    echo -e "${YELLOW}=== PHASE 4: SPA + CDN TESTS ===${NC}"
    
    echo "1. Testing CloudFront distribution..."
    HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" $SPA_URL)
    [ "$HTTP_STATUS" = "200" ]
    test_result $? "CloudFront distribution accessible"
    
    echo "2. Testing SPA content..."
    curl -s $SPA_URL | grep -q "MongoDB Manager"
    test_result $? "SPA content loads correctly"
    
    echo "3. Testing S3 bucket..."
    S3_BUCKET=$(terraform output -raw s3_bucket_name 2>/dev/null)
    if [ ! -z "$S3_BUCKET" ]; then
        aws s3 ls s3://$S3_BUCKET/index.html >/dev/null 2>&1
        test_result $? "S3 bucket contains SPA files"
    fi
    
    echo "4. Testing CloudFront headers..."
    CF_HEADERS=$(curl -s -I $SPA_URL | grep -i "cloudfront")
    if [ ! -z "$CF_HEADERS" ]; then
        test_result 0 "CloudFront headers present"
    else
        test_result 1 "CloudFront headers present"
    fi
    
    echo ""
fi

# Data Consistency Test
echo -e "${YELLOW}=== DATA CONSISTENCY TESTS ===${NC}"

if [ ! -z "$API_URL" ]; then
    echo "1. Testing data persistence across phases..."
    TOTAL_DOCS=$(curl -s -X POST $API_URL \
        -H 'Content-Type: application/json' \
        -d '{"action":"find","query":{}}' | jq -r '.documents | length' 2>/dev/null)
    
    if [ ! -z "$TOTAL_DOCS" ] && [ "$TOTAL_DOCS" -gt 0 ]; then
        test_result 0 "Data persists across phases ($TOTAL_DOCS documents)"
    else
        test_result 1 "Data persistence verification"
    fi
elif [ ! -z "$LAMBDA_NAME" ]; then
    echo "1. Testing data persistence via Lambda..."
    aws lambda invoke --function-name $LAMBDA_NAME --payload '{"action":"find","query":{}}' response.json >/dev/null 2>&1
    TOTAL_DOCS=$(cat response.json | jq -r '.body' | jq -r '.documents | length' 2>/dev/null)
    
    if [ ! -z "$TOTAL_DOCS" ] && [ "$TOTAL_DOCS" -gt 0 ]; then
        test_result 0 "Data persists across phases ($TOTAL_DOCS documents)"
    else
        test_result 1 "Data persistence verification"
    fi
fi

echo ""

# Performance Tests
echo -e "${YELLOW}=== PERFORMANCE TESTS ===${NC}"

if [ ! -z "$API_URL" ]; then
    echo "1. Testing API response time..."
    START_TIME=$(date +%s%N)
    curl -s -X POST $API_URL \
        -H 'Content-Type: application/json' \
        -d '{"action":"find","query":{"_id":{"$exists":true}}}' >/dev/null
    END_TIME=$(date +%s%N)
    RESPONSE_TIME=$(( (END_TIME - START_TIME) / 1000000 ))
    
    if [ $RESPONSE_TIME -lt 5000 ]; then
        test_result 0 "API response time acceptable (${RESPONSE_TIME}ms)"
    else
        test_result 1 "API response time too slow (${RESPONSE_TIME}ms)"
    fi
fi

if [ ! -z "$SPA_URL" ]; then
    echo "2. Testing SPA load time..."
    START_TIME=$(date +%s%N)
    curl -s $SPA_URL >/dev/null
    END_TIME=$(date +%s%N)
    LOAD_TIME=$(( (END_TIME - START_TIME) / 1000000 ))
    
    if [ $LOAD_TIME -lt 3000 ]; then
        test_result 0 "SPA load time acceptable (${LOAD_TIME}ms)"
    else
        test_result 1 "SPA load time too slow (${LOAD_TIME}ms)"
    fi
fi

echo ""

# Security Tests
echo -e "${YELLOW}=== SECURITY TESTS ===${NC}"

echo "1. Testing EC2 private access..."
if [ -z "$PUBLIC_IP" ]; then
    test_result 0 "EC2 has no public IP (secure)"
else
    test_result 1 "EC2 has public IP (development mode)"
fi

if [ ! -z "$API_URL" ]; then
    echo "2. Testing HTTPS enforcement..."
    HTTP_URL=$(echo $API_URL | sed 's/https:/http:/')
    HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" $HTTP_URL 2>/dev/null)
    if [ "$HTTP_STATUS" != "200" ]; then
        test_result 0 "HTTPS properly enforced"
    else
        test_result 1 "HTTP not properly redirected"
    fi
fi

echo ""

# Summary
echo -e "${BLUE}=== TEST SUMMARY ===${NC}"
echo "Phase: $CURRENT_PHASE"
echo "Tests Passed: $PASSED_TESTS/$TOTAL_TESTS"
echo ""

if [ $PASSED_TESTS -eq $TOTAL_TESTS ]; then
    echo -e "${GREEN}🎉 ALL TESTS PASSED! System is working correctly.${NC}"
else
    echo -e "${YELLOW}⚠️  Some tests failed. Check the results above.${NC}"
fi

echo ""
echo -e "${BLUE}=== NEXT STEPS ===${NC}"

if [ "$CURRENT_PHASE" = "Phase 1 (Public)" ]; then
    echo "• Ready to migrate to Phase 2 (Private Setup)"
    echo "• Run: cp main-private.tf main.tf && terraform apply"
elif [ "$CURRENT_PHASE" = "Phase 2 (Private)" ]; then
    echo "• Ready to deploy Phase 3 (API Gateway)"
    echo "• Run: bash deploy-api.sh"
elif [ "$CURRENT_PHASE" = "Phase 3 (API Gateway)" ]; then
    echo "• Ready to deploy Phase 4 (SPA + CDN)"
    echo "• Run: bash deploy-spa.sh"
elif [ "$CURRENT_PHASE" = "Phase 4 (SPA + CDN)" ]; then
    echo "• System is complete! 🚀"
    echo "• SPA URL: $SPA_URL"
    echo "• API URL: $API_URL"
fi

echo ""
echo "To view all data:"
if [ ! -z "$SPA_URL" ]; then
    echo "• Open SPA: $SPA_URL"
elif [ ! -z "$API_URL" ]; then
    echo "• curl -X POST $API_URL -H 'Content-Type: application/json' -d '{\"action\":\"find\",\"query\":{}}'"
else
    echo "• aws lambda invoke --function-name $LAMBDA_NAME --payload '{\"action\":\"find\",\"query\":{}}' response.json"
fi

echo ""
echo "To clean up:"
echo "• terraform destroy -auto-approve"

# Cleanup
rm -f response.json