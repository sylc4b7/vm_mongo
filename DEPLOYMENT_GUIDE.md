# MongoDB Lambda AWS Deployment Guide

## Prerequisites
```bash
# Install required tools
- AWS CLI configured: aws configure
- Terraform installed
- Python 3.9+ with pip
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
# 1. SSH to EC2
ssh -i ~/.ssh/id_rsa ubuntu@54.123.45.67

# 2. Check MongoDB on EC2
ubuntu@ip-10-0-1-123:~$ sudo systemctl status mongod
● mongod.service - MongoDB Database Server
   Active: active (running)

# 3. Test Lambda function
aws lambda invoke --function-name mongo-client \
  --payload '{"action":"insert","data":{"name":"test","value":123}}' \
  response.json

cat response.json
# Expected: {"statusCode": 200, "body": "{\"inserted_id\": \"...\"}"} 

# 4. Test find operation
aws lambda invoke --function-name mongo-client \
  --payload '{"action":"find","query":{}}' \
  response.json

cat response.json
# Expected: {"statusCode": 200, "body": "{\"documents\": [...]}"} 
```

## Success Criteria:
- ✅ EC2 has public IP and SSH access
- ✅ MongoDB running on EC2
- ✅ Lambda can connect to MongoDB
- ✅ Data persists in MongoDB

---

# Phase 2: Private Setup (Production)

## Files Used:
- `main-private.tf`
- `outputs-private.tf`

## Migration Steps:
```bash
# 1. Backup current config
cp main.tf main-public-backup.tf
cp outputs.tf outputs-public-backup.tf

# 2. Switch to private config
cp main-private.tf main.tf
cp outputs-private.tf outputs.tf

# 3. Apply changes
terraform plan
terraform apply
```

## Expected Outputs:
```
ec2_private_ip = "10.0.1.123"
lambda_function_name = "mongo-client"
# Note: No public IP output
```

## Tests:
```bash
# 1. Verify SSH is blocked
ssh -i ~/.ssh/id_rsa ubuntu@10.0.1.123
# Expected: Connection timeout (no public IP)

# 2. Test Lambda still works
aws lambda invoke --function-name mongo-client \
  --payload '{"action":"find","query":{}}' \
  response.json

cat response.json
# Expected: Previous data still exists

# 3. Test insert still works
aws lambda invoke --function-name mongo-client \
  --payload '{"action":"insert","data":{"phase":"2","secure":true}}' \
  response.json
```

## Success Criteria:
- ✅ No public IP on EC2
- ✅ SSH access blocked
- ✅ Lambda still connects to MongoDB
- ✅ Data from Phase 1 still exists
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
echo "API URL: $API_URL"

# 2. Test INSERT via curl
curl -X POST $API_URL \
  -H 'Content-Type: application/json' \
  -d '{"action":"insert","data":{"name":"John","age":30,"source":"internet"}}'

# Expected: {"inserted_id": "..."}

# 3. Test FIND via curl
curl -X POST $API_URL \
  -H 'Content-Type: application/json' \
  -d '{"action":"find","query":{}}'

# Expected: {"documents": [...]} (all data from all phases)

# 4. Test UPDATE via curl
curl -X POST $API_URL \
  -H 'Content-Type: application/json' \
  -d '{"action":"update","query":{"name":"John"},"update":{"$set":{"age":31}}}'

# Expected: {"modified_count": 1}

# 5. Test DELETE via curl
curl -X POST $API_URL \
  -H 'Content-Type: application/json' \
  -d '{"action":"delete","query":{"source":"internet"}}'

# Expected: {"deleted_count": 1}

# 6. Test CORS (from browser)
# Open browser console and run:
fetch('https://abcd1234.execute-api.us-east-1.amazonaws.com/prod/mongo', {
  method: 'POST',
  headers: {'Content-Type': 'application/json'},
  body: JSON.stringify({action: 'find', query: {}})
}).then(r => r.json()).then(console.log)
```

## Success Criteria:
- ✅ API Gateway endpoint accessible from internet
- ✅ CRUD operations work via HTTP
- ✅ CORS headers present for browser access
- ✅ EC2 still private (no SSH access)
- ✅ Data persists across all phases

---

# Troubleshooting

## Common Issues:

### Phase 1:
```bash
# SSH key issues
ls -la ~/.ssh/id_rsa*
# If missing: ssh-keygen -t rsa -b 2048 -f ~/.ssh/id_rsa -N ""

# MongoDB not starting
ssh ubuntu@<public_ip>
sudo journalctl -u mongod -f
```

### Phase 2:
```bash
# Lambda timeout in VPC
aws logs describe-log-groups --log-group-name-prefix /aws/lambda/mongo-client
aws logs describe-log-streams --log-group-name /aws/lambda/mongo-client
```

### Phase 3:
```bash
# API Gateway 502 errors
aws logs describe-log-streams --log-group-name /aws/lambda/mongo-client
aws logs get-log-events --log-group-name /aws/lambda/mongo-client --log-stream-name <stream>

# CORS issues
curl -X OPTIONS $API_URL -v
# Should return CORS headers
```

## Cleanup:
```bash
# Destroy all resources
terraform destroy -auto-approve

# Clean up files
rm -f *.zip response.json terraform.tfstate*
```

---

# Cost Estimation

## Free Tier (First 12 months):
- **EC2 t2.micro**: FREE (750 hours/month)
- **Lambda**: FREE (1M requests/month)
- **API Gateway**: FREE (1M requests/month)
- **Data Transfer**: FREE (1GB/month)
- **Total**: $0/month

## After Free Tier:
- **EC2 t2.micro**: ~$8.50/month
- **Lambda**: ~$0.20 per 1M requests
- **API Gateway**: ~$3.50 per 1M requests
- **Data Transfer**: ~$0.09/GB
- **Total**: ~$12-15/month for light usage