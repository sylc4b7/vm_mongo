# Complete MongoDB Lambda AWS Deployment Guide - All Phases

## Prerequisites
```bash
# Required tools
- AWS CLI configured: aws configure
- Terraform installed
- Python 3.9+ with pip
- Git Bash (Windows) or Terminal (Mac/Linux)
```

---

# Phase 1: Public Setup (Development)

## Files Used:
- `main.tf` (original)
- `outputs.tf` (original) 
- `deploy.sh`
- `lambda_function.py`
- `install_mongo.sh`

## Deployment Steps:
```bash
# 1. Deploy infrastructure
bash deploy.sh

# 2. Wait for completion (~5 minutes)
```

## Expected Outputs:
```
ec2_public_ip = "54.123.45.67"
ec2_private_ip = "10.0.1.123"
lambda_function_name = "mongo-client"
```

## Tests:
```bash
# 1. Test SSH access
ssh -i ~/.ssh/id_rsa ubuntu@$(terraform output -raw ec2_public_ip)

# 2. Check MongoDB on EC2
ubuntu@ip-10-0-1-123:~$ sudo systemctl status mongod
● mongod.service - MongoDB Database Server
   Active: active (running)

# 3. Test Lambda insert
aws lambda invoke --function-name mongo-client \
  --payload '{"action":"insert","data":{"phase":"1","test":"public"}}' \
  response.json && cat response.json

# Expected: {"statusCode": 200, "body": "{\"inserted_id\": \"...\"}"} 

# 4. Test Lambda find
aws lambda invoke --function-name mongo-client \
  --payload '{"action":"find","query":{"phase":"1"}}' \
  response.json && cat response.json

# Expected: {"statusCode": 200, "body": "{\"documents\": [...]}"} 
```

## Success Criteria:
- ✅ EC2 has public IP and SSH access works
- ✅ MongoDB running and accessible via SSH
- ✅ Lambda can insert and find documents
- ✅ All outputs present

---

# Phase 2: Private Setup (Production)

## Files Used:
- `main-private.tf`
- `outputs-private.tf`

## Migration Steps:
```bash
# 1. Backup current config
cp main.tf main-phase1-backup.tf
cp outputs.tf outputs-phase1-backup.tf

# 2. Switch to private config
cp main-private.tf main.tf
cp outputs-private.tf outputs.tf

# 3. Apply changes
terraform plan
terraform apply -auto-approve
```

## Expected Outputs:
```
ec2_private_ip = "10.0.1.123"
lambda_function_name = "mongo-client"
# Note: No ec2_public_ip output
```

## Tests:
```bash
# 1. Verify SSH is blocked
ssh -i ~/.ssh/id_rsa ubuntu@10.0.1.123
# Expected: Connection timeout (no route)

# 2. Test Lambda still works
aws lambda invoke --function-name mongo-client \
  --payload '{"action":"find","query":{"phase":"1"}}' \
  response.json && cat response.json
# Expected: Phase 1 data still exists

# 3. Test new insert in private mode
aws lambda invoke --function-name mongo-client \
  --payload '{"action":"insert","data":{"phase":"2","secure":true}}' \
  response.json && cat response.json
# Expected: Successful insert

# 4. Verify all data persists
aws lambda invoke --function-name mongo-client \
  --payload '{"action":"find","query":{}}' \
  response.json && cat response.json
# Expected: Both Phase 1 and Phase 2 data
```

## Success Criteria:
- ✅ No public IP on EC2
- ✅ SSH access completely blocked
- ✅ Lambda still connects to MongoDB privately
- ✅ All previous data intact
- ✅ New data can be inserted

---

# Phase 3: API Gateway (Internet Access)

## Files Used:
- `main-api.tf`
- `outputs-api.tf`
- `lambda_function_api.py`
- `deploy-api.sh`

## Deployment Steps:
```bash
# 1. Deploy API Gateway version
bash deploy-api.sh

# 2. Wait for completion (~3 minutes)
```

## Expected Outputs:
```
ec2_private_ip = "10.0.1.123"
lambda_function_name = "mongo-client"
api_gateway_url = "arn:aws:execute-api:us-east-1:123456789012:abcd1234/prod/mongo"
api_gateway_invoke_url = "https://abcd1234.execute-api.us-east-1.amazonaws.com/prod/mongo"
```

## Tests:
```bash
# 1. Get API URL
API_URL=$(terraform output -raw api_gateway_invoke_url)
echo "Testing API: $API_URL"

# 2. Test INSERT via curl
curl -X POST $API_URL \
  -H 'Content-Type: application/json' \
  -d '{"action":"insert","data":{"phase":"3","method":"curl","timestamp":"'$(date)'"}}' \
  | jq .
# Expected: {"inserted_id": "..."}

# 3. Test FIND via curl
curl -X POST $API_URL \
  -H 'Content-Type: application/json' \
  -d '{"action":"find","query":{"phase":"3"}}' \
  | jq .
# Expected: {"documents": [...]}

# 4. Test UPDATE via curl
curl -X POST $API_URL \
  -H 'Content-Type: application/json' \
  -d '{"action":"update","query":{"phase":"3"},"update":{"$set":{"updated":true}}}' \
  | jq .
# Expected: {"modified_count": 1}

# 5. Test DELETE via curl
curl -X POST $API_URL \
  -H 'Content-Type: application/json' \
  -d '{"action":"delete","query":{"method":"curl"}}' \
  | jq .
# Expected: {"deleted_count": 1}

# 6. Test CORS headers
curl -X OPTIONS $API_URL -v 2>&1 | grep -i "access-control"
# Expected: CORS headers present

# 7. Test from browser console
# Open browser and run:
fetch('$API_URL', {
  method: 'POST',
  headers: {'Content-Type': 'application/json'},
  body: JSON.stringify({action: 'find', query: {}})
}).then(r => r.json()).then(console.log)
```

## Success Criteria:
- ✅ API Gateway endpoint accessible from internet
- ✅ All CRUD operations work via HTTP
- ✅ CORS headers present for browser access
- ✅ EC2 still completely private
- ✅ Data from all phases persists

---

# Phase 4: Single Page Application + CDN

## Files Used:
- `main-spa.tf`
- `outputs-spa.tf`
- `index.html`
- `deploy-spa.sh`

## Deployment Steps:
```bash
# 1. Deploy SPA + CDN
bash deploy-spa.sh

# 2. Wait for CloudFront deployment (~10-15 minutes)
```

## Expected Outputs:
```
ec2_private_ip = "10.0.1.123"
lambda_function_name = "mongo-client"
api_gateway_invoke_url = "https://abcd1234.execute-api.us-east-1.amazonaws.com/prod/mongo"
s3_bucket_name = "mongo-spa-xyz12345"
s3_website_url = "http://mongo-spa-xyz12345.s3-website-us-east-1.amazonaws.com"
cloudfront_domain = "d123456789.cloudfront.net"
spa_url = "https://d123456789.cloudfront.net"
```

## Tests:
```bash
# 1. Get SPA URL
SPA_URL=$(terraform output -raw spa_url)
echo "SPA URL: $SPA_URL"

# 2. Test CloudFront distribution
curl -I $SPA_URL
# Expected: HTTP 200, CloudFront headers

# 3. Test SPA loads
curl -s $SPA_URL | grep -i "MongoDB Manager"
# Expected: HTML title found

# 4. Test S3 bucket directly
S3_BUCKET=$(terraform output -raw s3_bucket_name)
aws s3 ls s3://$S3_BUCKET/
# Expected: index.html listed

# 5. Manual browser tests:
echo "Open in browser: $SPA_URL"
echo ""
echo "Browser Test Checklist:"
echo "□ Page loads with 'MongoDB Manager' title"
echo "□ API URL is pre-configured"
echo "□ 'Test Connection' button works"
echo "□ Insert form accepts JSON data"
echo "□ Find button returns documents"
echo "□ Update form modifies documents"
echo "□ Delete button removes documents"
echo "□ All operations show success/error messages"
echo "□ Responsive design works on mobile"
```

## Manual SPA Testing:
```javascript
// Browser console tests
// 1. Test API connectivity
fetch('https://your-api-url/prod/mongo', {
  method: 'POST',
  headers: {'Content-Type': 'application/json'},
  body: JSON.stringify({action: 'find', query: {}})
}).then(r => r.json()).then(console.log)

// 2. Test insert via SPA
// Use the web interface to insert:
{"name": "SPA Test", "browser": "Chrome", "timestamp": "2024-01-01"}

// 3. Test find via SPA
// Query: {"name": "SPA Test"}

// 4. Test update via SPA
// Query: {"name": "SPA Test"}
// Update: {"$set": {"updated": true}}

// 5. Test delete via SPA
// Query: {"browser": "Chrome"}
```

## Success Criteria:
- ✅ CloudFront distribution deployed and accessible
- ✅ S3 static website hosting configured
- ✅ SPA loads in browser with proper styling
- ✅ API URL pre-configured in SPA
- ✅ All CRUD operations work via web interface
- ✅ Responsive design works on mobile devices
- ✅ Error handling displays user-friendly messages
- ✅ Data persists across all operations

---

# Complete System Test

## End-to-End Validation:
```bash
# 1. Run comprehensive test script
bash test-all-phases.sh

# 2. Verify data consistency across all phases
API_URL=$(terraform output -raw api_gateway_invoke_url)
curl -X POST $API_URL \
  -H 'Content-Type: application/json' \
  -d '{"action":"find","query":{}}' \
  | jq '.documents | length'
# Expected: Multiple documents from all phases

# 3. Test SPA functionality
SPA_URL=$(terraform output -raw spa_url)
echo "Complete system test:"
echo "1. Open: $SPA_URL"
echo "2. Verify all historical data is visible"
echo "3. Test all CRUD operations"
echo "4. Confirm real-time updates"
```

---

# Troubleshooting Guide

## Common Issues:

### Phase 1 Issues:
```bash
# SSH key problems
ls -la ~/.ssh/id_rsa*
# Fix: ssh-keygen -t rsa -b 2048 -f ~/.ssh/id_rsa -N ""

# MongoDB not starting
ssh ubuntu@$(terraform output -raw ec2_public_ip)
sudo journalctl -u mongod -f
# Fix: Check install_mongo.sh script
```

### Phase 2 Issues:
```bash
# Lambda VPC timeout
aws logs describe-log-groups --log-group-name-prefix /aws/lambda/mongo-client
# Fix: Check security group rules
```

### Phase 3 Issues:
```bash
# API Gateway 502 errors
aws logs get-log-events --log-group-name /aws/lambda/mongo-client --log-stream-name $(aws logs describe-log-streams --log-group-name /aws/lambda/mongo-client --query 'logStreams[0].logStreamName' --output text)
# Fix: Check Lambda function logs

# CORS issues
curl -X OPTIONS $(terraform output -raw api_gateway_invoke_url) -v
# Fix: Verify CORS configuration in Terraform
```

### Phase 4 Issues:
```bash
# CloudFront not serving content
aws cloudfront list-distributions --query 'DistributionList.Items[0].Status'
# Fix: Wait for deployment to complete

# SPA not loading
aws s3 ls s3://$(terraform output -raw s3_bucket_name)/
# Fix: Verify index.html uploaded correctly
```

---

# Cost Summary

## Free Tier (First 12 months):
- **EC2 t2.micro**: FREE (750 hours/month)
- **Lambda**: FREE (1M requests/month)
- **API Gateway**: FREE (1M requests/month)
- **S3**: FREE (5GB storage, 20K GET requests)
- **CloudFront**: FREE (50GB data transfer)
- **Data Transfer**: FREE (1GB/month)
- **Total**: $0/month

## After Free Tier:
- **EC2 t2.micro**: ~$8.50/month
- **Lambda**: ~$0.20 per 1M requests
- **API Gateway**: ~$3.50 per 1M requests
- **S3**: ~$0.50/month (light usage)
- **CloudFront**: ~$1-3/month (light usage)
- **Data Transfer**: ~$0.09/GB
- **Total**: ~$13-18/month for light usage

---

# Cleanup

## Destroy All Resources:
```bash
# Complete cleanup
terraform destroy -auto-approve

# Clean up local files
rm -f *.zip response.json terraform.tfstate* index_updated.html

# Verify cleanup
aws ec2 describe-instances --query 'Reservations[].Instances[?State.Name!=`terminated`]'
aws lambda list-functions --query 'Functions[?FunctionName==`mongo-client`]'
aws s3 ls | grep mongo-spa
```

---

# Architecture Evolution Summary

| Phase | Components | Access Method | Security Level | Use Case |
|-------|------------|---------------|----------------|----------|
| **Phase 1** | EC2 + Lambda | SSH + AWS CLI | Development | Setup & Testing |
| **Phase 2** | EC2 + Lambda | AWS CLI only | Production | Secure Backend |
| **Phase 3** | EC2 + Lambda + API Gateway | HTTP API | Production API | External Integration |
| **Phase 4** | EC2 + Lambda + API Gateway + S3 + CloudFront | Web Browser | Full Stack | End User Application |

Each phase builds upon the previous, maintaining data integrity while adding functionality and improving security! 🚀