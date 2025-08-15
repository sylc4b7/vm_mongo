# MongoDB Lambda AWS Deployment Guide

## Prerequisites
```bash
# Install required tools
- AWS CLI configured: aws configure
- Terraform installed
- Python 3.9+ with pip
- SSH key pair: ~/.ssh/id_rsa (public key in ~/.ssh/id_rsa.pub)
```

---

# Current Setup: API Gateway + Private EC2

## Files Used:
- `main.tf` - Infrastructure with VPC, EC2, Lambda, API Gateway
- `outputs.tf` - Outputs including public IP for testing
- `lambda_function.py` - Enhanced Lambda with API Gateway integration
- `install_mongo.sh` - MongoDB installation script
- `test-ec2-connectivity.sh` - EC2 and MongoDB connectivity tests
- `test-api-enhanced.sh` - Complete API testing suite

## Deployment Steps:
```bash
# 1. Create Lambda deployment package
zip lambda_function.zip lambda_function.py

# 2. Create pymongo layer
mkdir -p python/lib/python3.9/site-packages
pip install pymongo -t python/lib/python3.9/site-packages/
zip -r pymongo-layer.zip python/

# 3. Deploy infrastructure
terraform init
terraform plan
terraform apply

# 4. Wait for completion (~5-8 minutes)
```

## Expected Outputs:
```
ec2_public_ip = "44.203.243.211"
ec2_private_ip = "10.0.1.107"
lambda_function_name = "mongo-client"
api_gateway_base_url = "https://5crqbngzz8.execute-api.us-east-1.amazonaws.com/prod"
```

## Testing:

### 1. EC2 & MongoDB Connectivity Test:
```bash
# Run comprehensive connectivity test
bash test-ec2-connectivity.sh

# Expected results:
# ✅ SSH connectivity to EC2
# ✅ MongoDB service running
# ✅ MongoDB listening on port 27017
# ✅ MongoDB connection test
# ✅ Create test document
# ✅ Read test document
# ✅ Network rules configured
```

### 2. API Gateway Integration Test:
```bash
# Run complete API test suite
bash test-api-enhanced.sh

# Expected results:
# ✅ Health check endpoint
# ✅ Create documents
# ✅ Get all documents
# ✅ Get filtered documents
# ✅ Update documents
# ✅ Pagination
# ✅ CORS headers
# ✅ Error handling
# ✅ Delete documents
```

### 3. Manual API Testing:
```bash
# Get API URL
API_URL=$(terraform output -raw api_gateway_base_url)

# Health check
curl -X GET $API_URL/api/health

# Create document
curl -X POST $API_URL/api/documents \
  -H 'Content-Type: application/json' \
  -d '{"name":"test","status":"active"}'

# Get all documents
curl -X GET $API_URL/api/documents

# Get filtered documents
curl -X GET "$API_URL/api/documents?filter={\"status\":\"active\"}"

# Update documents
curl -X PUT $API_URL/api/documents \
  -H 'Content-Type: application/json' \
  -d '{"query":{"status":"active"},"update":{"$set":{"status":"completed"}}}'

# Delete documents
curl -X DELETE "$API_URL/api/documents?filter={\"status\":\"completed\"}"
```

## Success Criteria:
- ✅ EC2 has public IP for testing access
- ✅ MongoDB running on EC2 (mongosh available)
- ✅ Lambda connects to MongoDB via VPC
- ✅ API Gateway provides RESTful endpoints
- ✅ CORS enabled for browser access
- ✅ All CRUD operations working

---

# Production Hardening (Optional)

## Remove Public IP for Production:
```bash
# 1. Remove public IP assignment
# Edit main.tf, change:
# map_public_ip_on_launch = true
# to:
# map_public_ip_on_launch = false

# 2. Remove ec2_public_ip from outputs.tf

# 3. Apply changes
terraform plan
terraform apply
```

## Expected Changes:
- ❌ SSH access blocked (no public IP)
- ✅ API Gateway still works
- ✅ Lambda still connects via VPC
- ✅ MongoDB data preserved

## Security Improvements:
```bash
# 1. Restrict security group to Lambda only
# Edit main.tf security group rules

# 2. Enable VPC Flow Logs
# Add VPC flow logs resource

# 3. Add CloudWatch monitoring
# Add CloudWatch alarms for Lambda errors
```

---

# Troubleshooting

## Common Issues:

### SSH Connection Issues:
```bash
# Check SSH key exists
ls -la ~/.ssh/id_rsa*
# If missing: ssh-keygen -t rsa -b 2048 -f ~/.ssh/id_rsa -N ""

# Check key permissions
chmod 600 ~/.ssh/id_rsa

# Test SSH connection
ssh -i ~/.ssh/id_rsa ubuntu@$(terraform output -raw ec2_public_ip)
```

### MongoDB Issues:
```bash
# Check MongoDB status
ssh -i ~/.ssh/id_rsa ubuntu@$(terraform output -raw ec2_public_ip) "sudo systemctl status mongod"

# View MongoDB logs
ssh -i ~/.ssh/id_rsa ubuntu@$(terraform output -raw ec2_public_ip) "sudo journalctl -u mongod -f"

# Restart MongoDB
ssh -i ~/.ssh/id_rsa ubuntu@$(terraform output -raw ec2_public_ip) "sudo systemctl restart mongod"
```

### Lambda Issues:
```bash
# Check Lambda logs
aws logs tail /aws/lambda/mongo-client --follow

# Test Lambda directly
aws lambda invoke --function-name mongo-client \
  --payload '{"httpMethod":"GET","path":"/api/health"}' \
  response.json && cat response.json
```

### API Gateway Issues:
```bash
# Test health endpoint
curl -s $(terraform output -raw api_gateway_base_url)/api/health | jq

# Check CORS headers
curl -X OPTIONS $(terraform output -raw api_gateway_base_url)/api/documents -v

# Test with verbose output
curl -v -X GET $(terraform output -raw api_gateway_base_url)/api/documents
```

### Network Issues:
```bash
# Check security groups
aws ec2 describe-security-groups --group-names mongo-ec2-* mongo-lambda-*

# Check VPC configuration
aws ec2 describe-vpcs --filters "Name=tag:Name,Values=mongo-vpc"
```

## Cleanup:
```bash
# Destroy all resources
terraform destroy -auto-approve

# Clean up files
rm -f *.zip response.json terraform.tfstate* .terraform.lock.hcl
rm -rf .terraform/ python/
```

---

# Cost Estimation

## Current Setup Monthly Costs:

### Free Tier (First 12 months):
- **EC2 t3.micro**: FREE (750 hours/month)
- **EBS 8GB**: FREE (30GB/month)
- **Lambda**: FREE (1M requests/month)
- **API Gateway**: FREE (1M requests/month)
- **VPC/Networking**: FREE
- **Public IP**: FREE (dynamic IP)
- **Total**: **$0/month**

### After Free Tier:
- **EC2 t3.micro**: $8.47/month
- **EBS 8GB**: $0.80/month
- **Lambda**: $0.20 per 1M requests
- **API Gateway**: $3.50 per 1M requests
- **Data Transfer**: $0.09/GB
- **Total**: **~$9.27/month** (base) + usage

### Production Optimizations:
- Remove public IP: No cost change
- Use smaller EBS volume: Save ~$0.40/month
- Reserved Instance: Save ~30% on EC2
- **Optimized Total**: **~$6-8/month**

---

# Available Endpoints

## API Gateway Endpoints:
- `GET /api/health` - Health check
- `GET /api/documents` - List all documents
- `GET /api/documents?filter={"status":"active"}` - Filtered documents
- `GET /api/documents?limit=10&skip=0` - Paginated documents
- `POST /api/documents` - Create document
- `PUT /api/documents` - Update documents
- `DELETE /api/documents?filter={"status":"completed"}` - Delete documents

## Test Scripts:
- `test-ec2-connectivity.sh` - EC2 and MongoDB tests
- `test-api-enhanced.sh` - Complete API test suite
- `debug-tests.sh` - Debug failing tests