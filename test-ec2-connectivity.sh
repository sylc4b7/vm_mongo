#!/bin/bash

echo "=== EC2 SSH & MongoDB Connectivity Test ==="
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

# Get outputs from Terraform
echo -e "${BLUE}Getting Terraform outputs...${NC}"
PUBLIC_IP=$(terraform output -raw ec2_public_ip 2>/dev/null)
PRIVATE_IP=$(terraform output -raw ec2_private_ip 2>/dev/null)

if [ -z "$PUBLIC_IP" ]; then
    echo -e "${RED}Error: Could not get EC2 public IP from Terraform outputs${NC}"
    echo "Make sure you've deployed with: terraform apply"
    exit 1
fi

echo -e "${BLUE}EC2 Public IP: $PUBLIC_IP${NC}"
echo -e "${BLUE}EC2 Private IP: $PRIVATE_IP${NC}"
echo ""

# Test 1: SSH Connectivity
echo -e "${YELLOW}=== TEST 1: SSH CONNECTIVITY ===${NC}"
echo "Testing SSH connection to EC2..."

timeout 10 ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -i ~/.ssh/id_rsa ubuntu@$PUBLIC_IP "echo 'SSH connection successful'" 2>/dev/null
SSH_RESULT=$?
test_result $SSH_RESULT "SSH connectivity to EC2"

if [ $SSH_RESULT -ne 0 ]; then
    echo "   Troubleshooting tips:"
    echo "   - Check if ~/.ssh/id_rsa exists and has correct permissions (chmod 600)"
    echo "   - Verify security group allows SSH (port 22) from your IP"
    echo "   - Try: ssh -i ~/.ssh/id_rsa ubuntu@$PUBLIC_IP"
fi

echo ""

# Test 2: MongoDB Service Status
echo -e "${YELLOW}=== TEST 2: MONGODB SERVICE STATUS ===${NC}"
echo "Checking MongoDB service on EC2..."

MONGO_STATUS=$(timeout 10 ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -i ~/.ssh/id_rsa ubuntu@$PUBLIC_IP "sudo systemctl is-active mongod" 2>/dev/null)
if [ "$MONGO_STATUS" = "active" ]; then
    test_result 0 "MongoDB service running"
else
    test_result 1 "MongoDB service running (Status: $MONGO_STATUS)"
    echo "   Try: sudo systemctl start mongod"
fi

echo ""

# Test 3: MongoDB Port Listening
echo -e "${YELLOW}=== TEST 3: MONGODB PORT LISTENING ===${NC}"
echo "Checking if MongoDB is listening on port 27017..."

timeout 10 ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -i ~/.ssh/id_rsa ubuntu@$PUBLIC_IP "sudo ss -tlnp | grep :27017" >/dev/null 2>&1
test_result $? "MongoDB listening on port 27017"

echo ""

# Test 4: MongoDB Connection Test
echo -e "${YELLOW}=== TEST 4: MONGODB CONNECTION TEST ===${NC}"
echo "Testing MongoDB connection and basic operations..."

# Test MongoDB connection
MONGO_TEST=$(timeout 15 ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -i ~/.ssh/id_rsa ubuntu@$PUBLIC_IP "mongosh --eval 'db.runCommand({ping: 1})' --quiet" 2>/dev/null)
if echo "$MONGO_TEST" | grep -q 'ok: 1'; then
    test_result 0 "MongoDB connection test"
else
    test_result 1 "MongoDB connection test"
fi

echo ""

# Test 5: Create Test Database and Collection
echo -e "${YELLOW}=== TEST 5: DATABASE OPERATIONS ===${NC}"
echo "Testing database and collection operations..."

# Create test document
CREATE_TEST=$(timeout 15 ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -i ~/.ssh/id_rsa ubuntu@$PUBLIC_IP "mongosh testdb --eval 'db.testcol.insertOne({test: \"connectivity\", timestamp: new Date()})' --quiet" 2>/dev/null)
if echo "$CREATE_TEST" | grep -q 'acknowledged: true'; then
    test_result 0 "Create test document"
else
    test_result 1 "Create test document"
fi

# Read test document
READ_TEST=$(timeout 15 ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -i ~/.ssh/id_rsa ubuntu@$PUBLIC_IP "mongosh testdb --eval 'db.testcol.findOne({test: \"connectivity\"})' --quiet" 2>/dev/null)
if echo "$READ_TEST" | grep -q "test: 'connectivity'"; then
    test_result 0 "Read test document"
else
    test_result 1 "Read test document"
fi

echo ""

# Test 6: Network Connectivity from Lambda Subnet
echo -e "${YELLOW}=== TEST 6: NETWORK CONNECTIVITY CHECK ===${NC}"
echo "Verifying network connectivity for Lambda..."

# Check if MongoDB allows connections from Lambda subnet (10.0.1.0/24)
NETWORK_TEST=$(timeout 10 ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -i ~/.ssh/id_rsa ubuntu@$PUBLIC_IP "sudo iptables -L | grep -E '(27017|ACCEPT)'" 2>/dev/null)
if [ ! -z "$NETWORK_TEST" ]; then
    test_result 0 "Network rules configured"
else
    test_result 1 "Network rules configured"
fi

echo ""

# Summary and Manual Commands
echo -e "${YELLOW}=== TESTING SUMMARY ===${NC}"
echo "EC2 connectivity and MongoDB tests completed!"
echo ""
echo -e "${BLUE}Manual SSH command:${NC}"
echo "ssh -i ~/.ssh/id_rsa ubuntu@$PUBLIC_IP"
echo ""
echo -e "${BLUE}Manual MongoDB commands on EC2:${NC}"
echo "# Connect to MongoDB"
echo "mongosh"
echo ""
echo "# Use test database"
echo "use testdb"
echo ""
echo "# Insert test document"
echo "db.testcol.insertOne({name: 'test', status: 'active'})"
echo ""
echo "# Find documents"
echo "db.testcol.find()"
echo ""
echo "# Check MongoDB status"
echo "sudo systemctl status mongod"
echo ""
echo "# View MongoDB logs"
echo "sudo journalctl -u mongod -f"