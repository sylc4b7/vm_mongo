#!/bin/bash

echo "=== Enhanced MongoDB API Gateway Testing Script ==="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test function
test_result() {
    if [ $1 -eq 0 ]; then
        echo -e "${GREEN}✅ PASS${NC}: $2"
    else
        echo -e "${RED}❌ FAIL${NC}: $2"
    fi
}

# Get API Gateway URL and API Key from Terraform output
API_BASE_URL=$(terraform output -raw api_gateway_base_url 2>/dev/null)
API_KEY=$(terraform output -raw api_key_value 2>/dev/null)

if [ -z "$API_BASE_URL" ]; then
    echo -e "${RED}Error: Could not get API Gateway URL from Terraform outputs${NC}"
    echo "Make sure you've deployed the infrastructure with: terraform apply"
    exit 1
fi

if [ -z "$API_KEY" ]; then
    echo -e "${RED}Error: Could not get API Key from Terraform outputs${NC}"
    echo "Make sure you've deployed the infrastructure with: terraform apply"
    exit 1
fi

echo -e "${BLUE}API Base URL: $API_BASE_URL${NC}"
echo -e "${BLUE}API Key: ${API_KEY:0:10}...${NC}"
echo ""

# Test 1: Health Check
echo -e "${YELLOW}=== TEST 1: HEALTH CHECK ===${NC}"
HEALTH_URL="$API_BASE_URL/api/health"
echo "Testing: GET $HEALTH_URL"

RESPONSE=$(curl -s -w "HTTPSTATUS:%{http_code}" -X GET "$HEALTH_URL")
HTTP_STATUS=$(echo $RESPONSE | tr -d '\n' | sed -e 's/.*HTTPSTATUS://')
RESPONSE_BODY=$(echo $RESPONSE | sed -e 's/HTTPSTATUS:.*//g')

if [ "$HTTP_STATUS" -eq 200 ]; then
    test_result 0 "Health check endpoint"
    echo "   Response: $RESPONSE_BODY" | jq '.' 2>/dev/null || echo "   Response: $RESPONSE_BODY"
else
    test_result 1 "Health check endpoint (HTTP $HTTP_STATUS)"
    echo "   Response: $RESPONSE_BODY"
fi

echo ""

# Test 2: Create Documents
echo -e "${YELLOW}=== TEST 2: CREATE DOCUMENTS ===${NC}"
DOCUMENTS_URL="$API_BASE_URL/api/documents"

# Create test document 1
echo "Creating document 1..."
RESPONSE=$(curl -s -w "HTTPSTATUS:%{http_code}" -X POST "$DOCUMENTS_URL" \
    -H 'Content-Type: application/json' \
    -H "X-API-Key: $API_KEY" \
    -d '{"name":"Test Document 1","status":"active","category":"test","priority":1}')

HTTP_STATUS=$(echo $RESPONSE | tr -d '\n' | sed -e 's/.*HTTPSTATUS://')
RESPONSE_BODY=$(echo $RESPONSE | sed -e 's/HTTPSTATUS:.*//g')

if [ "$HTTP_STATUS" -eq 201 ]; then
    test_result 0 "Create document 1"
    DOC1_ID=$(echo "$RESPONSE_BODY" | jq -r '.inserted_id' 2>/dev/null)
    echo "   Document ID: $DOC1_ID"
else
    test_result 1 "Create document 1 (HTTP $HTTP_STATUS)"
    echo "   Response: $RESPONSE_BODY"
fi

# Create test document 2
echo "Creating document 2..."
RESPONSE=$(curl -s -w "HTTPSTATUS:%{http_code}" -X POST "$DOCUMENTS_URL" \
    -H 'Content-Type: application/json' \
    -H "X-API-Key: $API_KEY" \
    -d '{"name":"Test Document 2","status":"pending","category":"test","priority":2}')

HTTP_STATUS=$(echo $RESPONSE | tr -d '\n' | sed -e 's/.*HTTPSTATUS://')
if [ "$HTTP_STATUS" -eq 201 ]; then
    test_result 0 "Create document 2"
    DOC2_ID=$(echo $RESPONSE | sed -e 's/HTTPSTATUS:.*//g' | jq -r '.inserted_id' 2>/dev/null)
    echo "   Document ID: $DOC2_ID"
else
    test_result 1 "Create document 2 (HTTP $HTTP_STATUS)"
fi

echo ""

# Test 3: Get All Documents
echo -e "${YELLOW}=== TEST 3: GET ALL DOCUMENTS ===${NC}"
echo "Testing: GET $DOCUMENTS_URL"

RESPONSE=$(curl -s -w "HTTPSTATUS:%{http_code}" -X GET "$DOCUMENTS_URL" \
    -H "X-API-Key: $API_KEY")
HTTP_STATUS=$(echo $RESPONSE | tr -d '\n' | sed -e 's/.*HTTPSTATUS://')
RESPONSE_BODY=$(echo $RESPONSE | sed -e 's/HTTPSTATUS:.*//g')

if [ "$HTTP_STATUS" -eq 200 ]; then
    test_result 0 "Get all documents"
    DOC_COUNT=$(echo "$RESPONSE_BODY" | jq '.count' 2>/dev/null)
    echo "   Found $DOC_COUNT documents"
else
    test_result 1 "Get all documents (HTTP $HTTP_STATUS)"
    echo "   Response: $RESPONSE_BODY"
fi

echo ""

# Test 4: Get Filtered Documents
echo -e "${YELLOW}=== TEST 4: GET FILTERED DOCUMENTS ===${NC}"
# Use curl with proper URL encoding
FILTER_JSON='{"status":"active"}'
echo "Testing: GET $DOCUMENTS_URL?filter=$FILTER_JSON"

RESPONSE=$(curl -s -w "HTTPSTATUS:%{http_code}" -X GET "$DOCUMENTS_URL" \
    -H "X-API-Key: $API_KEY" \
    --data-urlencode "filter=$FILTER_JSON" -G)
HTTP_STATUS=$(echo $RESPONSE | tr -d '\n' | sed -e 's/.*HTTPSTATUS://')
RESPONSE_BODY=$(echo $RESPONSE | sed -e 's/HTTPSTATUS:.*//g')

if [ "$HTTP_STATUS" -eq 200 ]; then
    test_result 0 "Get filtered documents (status=active)"
    ACTIVE_COUNT=$(echo "$RESPONSE_BODY" | jq '.count' 2>/dev/null)
    echo "   Found $ACTIVE_COUNT active documents"
else
    test_result 1 "Get filtered documents (HTTP $HTTP_STATUS)"
    echo "   Response: $RESPONSE_BODY"
fi

echo ""

# Test 5: Update Documents
echo -e "${YELLOW}=== TEST 5: UPDATE DOCUMENTS ===${NC}"
echo "Updating documents with status 'pending' to 'in-progress'..."

RESPONSE=$(curl -s -w "HTTPSTATUS:%{http_code}" -X PUT "$DOCUMENTS_URL" \
    -H 'Content-Type: application/json' \
    -H "X-API-Key: $API_KEY" \
    -d '{"query":{"status":"pending"},"update":{"$set":{"status":"in-progress","updated_by":"test-script"}}}')

HTTP_STATUS=$(echo $RESPONSE | tr -d '\n' | sed -e 's/.*HTTPSTATUS://')
RESPONSE_BODY=$(echo $RESPONSE | sed -e 's/HTTPSTATUS:.*//g')

if [ "$HTTP_STATUS" -eq 200 ]; then
    test_result 0 "Update documents"
    MODIFIED_COUNT=$(echo "$RESPONSE_BODY" | jq '.modified_count' 2>/dev/null)
    echo "   Modified $MODIFIED_COUNT documents"
else
    test_result 1 "Update documents (HTTP $HTTP_STATUS)"
    echo "   Response: $RESPONSE_BODY"
fi

echo ""

# Test 6: Pagination
echo -e "${YELLOW}=== TEST 6: PAGINATION ===${NC}"
PAGINATION_URL="$DOCUMENTS_URL?limit=1&skip=0"
echo "Testing: GET $PAGINATION_URL"

RESPONSE=$(curl -s -w "HTTPSTATUS:%{http_code}" -X GET "$PAGINATION_URL" \
    -H "X-API-Key: $API_KEY")
HTTP_STATUS=$(echo $RESPONSE | tr -d '\n' | sed -e 's/.*HTTPSTATUS://')
RESPONSE_BODY=$(echo $RESPONSE | sed -e 's/HTTPSTATUS:.*//g')

if [ "$HTTP_STATUS" -eq 200 ]; then
    test_result 0 "Pagination (limit=1)"
    RETURNED_COUNT=$(echo "$RESPONSE_BODY" | jq '.count' 2>/dev/null)
    TOTAL_COUNT=$(echo "$RESPONSE_BODY" | jq '.total' 2>/dev/null)
    echo "   Returned $RETURNED_COUNT of $TOTAL_COUNT total documents"
else
    test_result 1 "Pagination (HTTP $HTTP_STATUS)"
    echo "   Response: $RESPONSE_BODY"
fi

echo ""

# Test 7: CORS Headers
echo -e "${YELLOW}=== TEST 7: CORS HEADERS ===${NC}"
echo "Testing OPTIONS request for CORS..."

RESPONSE=$(curl -s -I -X OPTIONS "$DOCUMENTS_URL")
CORS_ORIGIN=$(echo "$RESPONSE" | grep -i "access-control-allow-origin" | tr -d '\r')
CORS_METHODS=$(echo "$RESPONSE" | grep -i "access-control-allow-methods" | tr -d '\r')

if [ ! -z "$CORS_ORIGIN" ] && [ ! -z "$CORS_METHODS" ]; then
    test_result 0 "CORS headers present"
    echo "   Origin: $CORS_ORIGIN"
    echo "   Methods: $CORS_METHODS"
else
    test_result 1 "CORS headers present"
fi

echo ""

# Test 8: Error Handling
echo -e "${YELLOW}=== TEST 8: ERROR HANDLING ===${NC}"
echo "Testing invalid JSON..."

RESPONSE=$(curl -s -w "HTTPSTATUS:%{http_code}" -X POST "$DOCUMENTS_URL" \
    -H 'Content-Type: application/json' \
    -d 'invalid json')

HTTP_STATUS=$(echo $RESPONSE | tr -d '\n' | sed -e 's/.*HTTPSTATUS://')

if [ "$HTTP_STATUS" -eq 400 ]; then
    test_result 0 "Invalid JSON handling"
else
    test_result 1 "Invalid JSON handling (expected 400, got $HTTP_STATUS)"
fi

echo ""

# Test 9: Delete Documents
echo -e "${YELLOW}=== TEST 9: DELETE DOCUMENTS ===${NC}"
# Use curl with proper URL encoding
DELETE_FILTER_JSON='{"category":"test"}'
echo "Deleting test documents..."

RESPONSE=$(curl -s -w "HTTPSTATUS:%{http_code}" -X DELETE "$DOCUMENTS_URL" \
    -H "X-API-Key: $API_KEY" \
    --data-urlencode "filter=$DELETE_FILTER_JSON" -G)
HTTP_STATUS=$(echo $RESPONSE | tr -d '\n' | sed -e 's/.*HTTPSTATUS://')
RESPONSE_BODY=$(echo $RESPONSE | sed -e 's/HTTPSTATUS:.*//g')

if [ "$HTTP_STATUS" -eq 200 ]; then
    test_result 0 "Delete documents"
    DELETED_COUNT=$(echo "$RESPONSE_BODY" | jq '.deleted_count' 2>/dev/null)
    echo "   Deleted $DELETED_COUNT documents"
else
    test_result 1 "Delete documents (HTTP $HTTP_STATUS)"
    echo "   Response: $RESPONSE_BODY"
fi

echo ""

# Summary
echo -e "${YELLOW}=== TESTING SUMMARY ===${NC}"
echo "All API Gateway proxy integration tests completed!"
echo ""
echo -e "${BLUE}Available Endpoints:${NC}"
echo "  GET  $API_BASE_URL/api/health"
echo "  GET  $API_BASE_URL/api/documents"
echo "  POST $API_BASE_URL/api/documents"
echo "  PUT  $API_BASE_URL/api/documents"
echo "  DELETE $API_BASE_URL/api/documents"
echo ""
echo -e "${BLUE}For manual testing, try these curl commands:${NC}"
echo ""
echo "# Health check"
echo "curl -X GET $API_BASE_URL/api/health"
echo ""
echo "# Create a document"
echo "curl -X POST $API_BASE_URL/api/documents \\"
echo "  -H 'Content-Type: application/json' \\"
echo "  -H 'X-API-Key: $API_KEY' \\"
echo "  -d '{\"name\":\"My Document\",\"status\":\"active\"}'"
echo ""
echo "# Get all documents"
echo "curl -X GET $API_BASE_URL/api/documents -H 'X-API-Key: $API_KEY'"
echo ""
echo "# Get filtered documents"
echo "curl -X GET '$API_BASE_URL/api/documents?filter={\"status\":\"active\"}' -H 'X-API-Key: $API_KEY'"
echo ""
echo "# Update documents"
echo "curl -X PUT $API_BASE_URL/api/documents \\"
echo "  -H 'Content-Type: application/json' \\"
echo "  -H 'X-API-Key: $API_KEY' \\"
echo "  -d '{\"query\":{\"status\":\"active\"},\"update\":{\"\$set\":{\"status\":\"completed\"}}}'"
echo ""
echo "# Delete documents"
echo "curl -X DELETE '$API_BASE_URL/api/documents?filter={\"status\":\"completed\"}' -H 'X-API-Key: $API_KEY'"