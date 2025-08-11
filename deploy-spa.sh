#!/bin/bash

echo "🚀 Deploying Phase 4: Single Page Application + CDN"
echo "=================================================="

# Create Lambda deployment package
zip lambda_function.zip lambda_function_api.py

# Create pymongo layer
mkdir -p python
pip install pymongo -t python/
zip -r pymongo-layer.zip python/
rm -rf python/

# Deploy infrastructure
cp main-spa.tf main.tf
cp outputs-spa.tf outputs.tf

terraform init
terraform plan
terraform apply -auto-approve

# Get outputs
S3_BUCKET=$(terraform output -raw s3_bucket_name)
API_URL=$(terraform output -raw api_gateway_invoke_url)
CLOUDFRONT_URL=$(terraform output -raw spa_url)

echo ""
echo "📁 Uploading SPA files to S3..."

# Update index.html with API URL
sed "s|placeholder=\"https://your-api-gateway-url/prod/mongo\"|value=\"$API_URL\"|g" index.html > index_updated.html

# Upload to S3
aws s3 cp index_updated.html s3://$S3_BUCKET/index.html --content-type "text/html"

# Wait for CloudFront deployment
echo ""
echo "⏳ Waiting for CloudFront distribution to deploy (this may take 10-15 minutes)..."
echo "You can check status at: https://console.aws.amazon.com/cloudfront/"

echo ""
echo "🎉 Deployment Complete!"
echo "======================="
echo ""
echo "📱 Single Page Application:"
echo "   $CLOUDFRONT_URL"
echo ""
echo "🔗 API Gateway URL:"
echo "   $API_URL"
echo ""
echo "📦 S3 Bucket:"
echo "   $S3_BUCKET"
echo ""
echo "🧪 Test the SPA:"
echo "   1. Open: $CLOUDFRONT_URL"
echo "   2. The API URL should be pre-configured"
echo "   3. Click 'Test Connection' to verify"
echo "   4. Use the web interface for CRUD operations"
echo ""
echo "💡 Note: CloudFront may take 10-15 minutes to fully propagate"
echo "    If the site doesn't load immediately, please wait and try again"

# Cleanup
rm -f index_updated.html