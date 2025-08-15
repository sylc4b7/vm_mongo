#!/bin/bash

echo "=== Enhanced MongoDB API Gateway Deployment (Fixed) ==="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check if required files exist
if [ ! -f "variables.tf" ]; then
    echo -e "${RED}Error: variables.tf not found${NC}"
    exit 1
fi

if [ ! -f "install_mongo.sh" ]; then
    echo -e "${RED}Error: install_mongo.sh not found${NC}"
    exit 1
fi

echo -e "${YELLOW}Step 1: Cleaning up conflicting files...${NC}"

# Backup all current files
if [ -f "main.tf" ]; then
    cp main.tf main.tf.backup
    echo "   Backed up main.tf"
fi

if [ -f "outputs.tf" ]; then
    cp outputs.tf outputs.tf.backup
    echo "   Backed up outputs.tf"
fi

if [ -f "lambda_function.py" ]; then
    cp lambda_function.py lambda_function.py.backup
    echo "   Backed up lambda_function.py"
fi

# Remove conflicting standalone files (they'll be integrated into main.tf)
if [ -f "api-gateway-enhanced.tf" ]; then
    mv api-gateway-enhanced.tf api-gateway-enhanced.tf.backup
    echo "   Moved api-gateway-enhanced.tf to backup (will be integrated)"
fi

if [ -f "outputs-enhanced.tf" ]; then
    mv outputs-enhanced.tf outputs-enhanced.tf.backup
    echo "   Moved outputs-enhanced.tf to backup (will be integrated)"
fi

echo -e "${GREEN}   Cleanup completed${NC}"

echo -e "${YELLOW}Step 2: Creating integrated main.tf...${NC}"

# Create complete main.tf with everything integrated
cat > main.tf << 'EOF'
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# VPC
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
  
  tags = {
    Name = "mongo-vpc"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  
  tags = {
    Name = "mongo-igw"
  }
}

# Subnet
resource "aws_subnet" "main" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true
  
  tags = {
    Name = "mongo-subnet"
  }
}

# Route Table
resource "aws_route_table" "main" {
  vpc_id = aws_vpc.main.id
  
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
  
  tags = {
    Name = "mongo-rt"
  }
}

resource "aws_route_table_association" "main" {
  subnet_id      = aws_subnet.main.id
  route_table_id = aws_route_table.main.id
}

# Security Groups
resource "aws_security_group" "ec2" {
  name_prefix = "mongo-ec2-"
  vpc_id      = aws_vpc.main.id
  
  ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    cidr_blocks     = ["0.0.0.0/0"]
  }
  
  ingress {
    from_port       = 27017
    to_port         = 27017
    protocol        = "tcp"
    security_groups = [aws_security_group.lambda.id]
  }
  
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "lambda" {
  name_prefix = "mongo-lambda-"
  vpc_id      = aws_vpc.main.id
  
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Key Pair
resource "aws_key_pair" "main" {
  key_name   = "mongo-key"
  public_key = file(var.public_key_path)
}

# EC2 Instance
resource "aws_instance" "mongo" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t3.micro"
  key_name              = aws_key_pair.main.key_name
  vpc_security_group_ids = [aws_security_group.ec2.id]
  subnet_id             = aws_subnet.main.id
  
  user_data = file("${path.module}/install_mongo.sh")
  
  tags = {
    Name = "mongo-server"
  }
}

# Lambda IAM Role
resource "aws_iam_role" "lambda" {
  name = "mongo-lambda-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_vpc" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# Lambda Function
resource "aws_lambda_function" "mongo_client" {
  filename         = "lambda_function.zip"
  function_name    = "mongo-client"
  role            = aws_iam_role.lambda.arn
  handler         = "lambda_function.lambda_handler"
  runtime         = "python3.9"
  timeout         = 30
  
  vpc_config {
    subnet_ids         = [aws_subnet.main.id]
    security_group_ids = [aws_security_group.lambda.id]
  }
  
  environment {
    variables = {
      MONGO_HOST = aws_instance.mongo.private_ip
    }
  }
  
  layers = [aws_lambda_layer_version.pymongo.arn]
}

# Lambda Layer for pymongo
resource "aws_lambda_layer_version" "pymongo" {
  filename   = "pymongo-layer.zip"
  layer_name = "pymongo"
  
  compatible_runtimes = ["python3.9"]
}

# API Gateway REST API
resource "aws_api_gateway_rest_api" "mongo_api" {
  name        = "mongo-api-enhanced"
  description = "Enhanced MongoDB API Gateway with multiple endpoints"
  
  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

# Root resource for /api
resource "aws_api_gateway_resource" "api" {
  rest_api_id = aws_api_gateway_rest_api.mongo_api.id
  parent_id   = aws_api_gateway_rest_api.mongo_api.root_resource_id
  path_part   = "api"
}

# Resource for /api/documents
resource "aws_api_gateway_resource" "documents" {
  rest_api_id = aws_api_gateway_rest_api.mongo_api.id
  parent_id   = aws_api_gateway_resource.api.id
  path_part   = "documents"
}

# Resource for /api/health
resource "aws_api_gateway_resource" "health" {
  rest_api_id = aws_api_gateway_rest_api.mongo_api.id
  parent_id   = aws_api_gateway_resource.api.id
  path_part   = "health"
}

# Methods for /api/documents
resource "aws_api_gateway_method" "documents_get" {
  rest_api_id   = aws_api_gateway_rest_api.mongo_api.id
  resource_id   = aws_api_gateway_resource.documents.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_method" "documents_post" {
  rest_api_id   = aws_api_gateway_rest_api.mongo_api.id
  resource_id   = aws_api_gateway_resource.documents.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_method" "documents_put" {
  rest_api_id   = aws_api_gateway_rest_api.mongo_api.id
  resource_id   = aws_api_gateway_resource.documents.id
  http_method   = "PUT"
  authorization = "NONE"
}

resource "aws_api_gateway_method" "documents_delete" {
  rest_api_id   = aws_api_gateway_rest_api.mongo_api.id
  resource_id   = aws_api_gateway_resource.documents.id
  http_method   = "DELETE"
  authorization = "NONE"
}

resource "aws_api_gateway_method" "health_get" {
  rest_api_id   = aws_api_gateway_rest_api.mongo_api.id
  resource_id   = aws_api_gateway_resource.health.id
  http_method   = "GET"
  authorization = "NONE"
}

# Lambda Proxy Integrations
resource "aws_api_gateway_integration" "documents_get" {
  rest_api_id = aws_api_gateway_rest_api.mongo_api.id
  resource_id = aws_api_gateway_resource.documents.id
  http_method = aws_api_gateway_method.documents_get.http_method
  
  integration_http_method = "POST"
  type                   = "AWS_PROXY"
  uri                    = aws_lambda_function.mongo_client.invoke_arn
}

resource "aws_api_gateway_integration" "documents_post" {
  rest_api_id = aws_api_gateway_rest_api.mongo_api.id
  resource_id = aws_api_gateway_resource.documents.id
  http_method = aws_api_gateway_method.documents_post.http_method
  
  integration_http_method = "POST"
  type                   = "AWS_PROXY"
  uri                    = aws_lambda_function.mongo_client.invoke_arn
}

resource "aws_api_gateway_integration" "documents_put" {
  rest_api_id = aws_api_gateway_rest_api.mongo_api.id
  resource_id = aws_api_gateway_resource.documents.id
  http_method = aws_api_gateway_method.documents_put.http_method
  
  integration_http_method = "POST"
  type                   = "AWS_PROXY"
  uri                    = aws_lambda_function.mongo_client.invoke_arn
}

resource "aws_api_gateway_integration" "documents_delete" {
  rest_api_id = aws_api_gateway_rest_api.mongo_api.id
  resource_id = aws_api_gateway_resource.documents.id
  http_method = aws_api_gateway_method.documents_delete.http_method
  
  integration_http_method = "POST"
  type                   = "AWS_PROXY"
  uri                    = aws_lambda_function.mongo_client.invoke_arn
}

resource "aws_api_gateway_integration" "health_get" {
  rest_api_id = aws_api_gateway_rest_api.mongo_api.id
  resource_id = aws_api_gateway_resource.health.id
  http_method = aws_api_gateway_method.health_get.http_method
  
  integration_http_method = "POST"
  type                   = "AWS_PROXY"
  uri                    = aws_lambda_function.mongo_client.invoke_arn
}

# CORS Support
resource "aws_api_gateway_method" "documents_options" {
  rest_api_id   = aws_api_gateway_rest_api.mongo_api.id
  resource_id   = aws_api_gateway_resource.documents.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_method" "health_options" {
  rest_api_id   = aws_api_gateway_rest_api.mongo_api.id
  resource_id   = aws_api_gateway_resource.health.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "documents_options" {
  rest_api_id = aws_api_gateway_rest_api.mongo_api.id
  resource_id = aws_api_gateway_resource.documents.id
  http_method = aws_api_gateway_method.documents_options.http_method
  
  type = "MOCK"
  request_templates = {
    "application/json" = jsonencode({
      statusCode = 200
    })
  }
}

resource "aws_api_gateway_integration" "health_options" {
  rest_api_id = aws_api_gateway_rest_api.mongo_api.id
  resource_id = aws_api_gateway_resource.health.id
  http_method = aws_api_gateway_method.health_options.http_method
  
  type = "MOCK"
  request_templates = {
    "application/json" = jsonencode({
      statusCode = 200
    })
  }
}

resource "aws_api_gateway_method_response" "documents_options" {
  rest_api_id = aws_api_gateway_rest_api.mongo_api.id
  resource_id = aws_api_gateway_resource.documents.id
  http_method = aws_api_gateway_method.documents_options.http_method
  status_code = "200"
  
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_method_response" "health_options" {
  rest_api_id = aws_api_gateway_rest_api.mongo_api.id
  resource_id = aws_api_gateway_resource.health.id
  http_method = aws_api_gateway_method.health_options.http_method
  status_code = "200"
  
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_integration_response" "documents_options" {
  rest_api_id = aws_api_gateway_rest_api.mongo_api.id
  resource_id = aws_api_gateway_resource.documents.id
  http_method = aws_api_gateway_method.documents_options.http_method
  status_code = aws_api_gateway_method_response.documents_options.status_code
  
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'"
    "method.response.header.Access-Control-Allow-Methods" = "'GET,POST,PUT,DELETE,OPTIONS'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
}

resource "aws_api_gateway_integration_response" "health_options" {
  rest_api_id = aws_api_gateway_rest_api.mongo_api.id
  resource_id = aws_api_gateway_resource.health.id
  http_method = aws_api_gateway_method.health_options.http_method
  status_code = aws_api_gateway_method_response.health_options.status_code
  
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'"
    "method.response.header.Access-Control-Allow-Methods" = "'GET,OPTIONS'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
}

# Lambda Permission for API Gateway
resource "aws_lambda_permission" "api_gw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.mongo_client.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.mongo_api.execution_arn}/*/*"
}

# API Gateway Deployment
resource "aws_api_gateway_deployment" "mongo_api" {
  depends_on = [
    aws_api_gateway_method.documents_get,
    aws_api_gateway_method.documents_post,
    aws_api_gateway_method.documents_put,
    aws_api_gateway_method.documents_delete,
    aws_api_gateway_method.health_get,
    aws_api_gateway_integration.documents_get,
    aws_api_gateway_integration.documents_post,
    aws_api_gateway_integration.documents_put,
    aws_api_gateway_integration.documents_delete,
    aws_api_gateway_integration.health_get,
  ]
  
  rest_api_id = aws_api_gateway_rest_api.mongo_api.id
  stage_name  = "prod"
}

# Data sources
data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]
  
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
  }
}
EOF

echo -e "${GREEN}   Integrated main.tf created${NC}"

echo -e "${YELLOW}Step 3: Creating integrated outputs.tf...${NC}"

cat > outputs.tf << 'EOF'
output "ec2_private_ip" {
  description = "Private IP of EC2 instance"
  value       = aws_instance.mongo.private_ip
}

output "lambda_function_name" {
  description = "Lambda function name"
  value       = aws_lambda_function.mongo_client.function_name
}

output "api_gateway_id" {
  description = "API Gateway REST API ID"
  value       = aws_api_gateway_rest_api.mongo_api.id
}

output "api_gateway_base_url" {
  description = "API Gateway base URL"
  value       = "https://${aws_api_gateway_rest_api.mongo_api.id}.execute-api.${var.aws_region}.amazonaws.com/prod"
}

output "api_endpoints" {
  description = "Available API endpoints for testing"
  value = {
    health_check = "https://${aws_api_gateway_rest_api.mongo_api.id}.execute-api.${var.aws_region}.amazonaws.com/prod/api/health"
    documents_base = "https://${aws_api_gateway_rest_api.mongo_api.id}.execute-api.${var.aws_region}.amazonaws.com/prod/api/documents"
  }
}

output "curl_examples" {
  description = "Example curl commands for testing"
  value = {
    health_check = "curl -X GET https://${aws_api_gateway_rest_api.mongo_api.id}.execute-api.${var.aws_region}.amazonaws.com/prod/api/health"
    
    create_document = "curl -X POST https://${aws_api_gateway_rest_api.mongo_api.id}.execute-api.${var.aws_region}.amazonaws.com/prod/api/documents -H 'Content-Type: application/json' -d '{\"name\":\"test\",\"status\":\"active\"}'"
    
    get_all_documents = "curl -X GET https://${aws_api_gateway_rest_api.mongo_api.id}.execute-api.${var.aws_region}.amazonaws.com/prod/api/documents"
    
    get_filtered_documents = "curl -X GET 'https://${aws_api_gateway_rest_api.mongo_api.id}.execute-api.${var.aws_region}.amazonaws.com/prod/api/documents?filter={\"status\":\"active\"}'"
    
    update_documents = "curl -X PUT https://${aws_api_gateway_rest_api.mongo_api.id}.execute-api.${var.aws_region}.amazonaws.com/prod/api/documents -H 'Content-Type: application/json' -d '{\"query\":{\"status\":\"active\"},\"update\":{\"$set\":{\"status\":\"completed\"}}}'"
    
    delete_documents = "curl -X DELETE 'https://${aws_api_gateway_rest_api.mongo_api.id}.execute-api.${var.aws_region}.amazonaws.com/prod/api/documents?filter={\"status\":\"completed\"}'"
  }
}
EOF

echo -e "${GREEN}   Integrated outputs.tf created${NC}"

echo -e "${YELLOW}Step 4: Updating Lambda function...${NC}"

# Copy enhanced lambda function
cp lambda_function_enhanced.py lambda_function.py
echo -e "${GREEN}   Lambda function updated${NC}"

echo -e "${YELLOW}Step 5: Packaging Lambda function...${NC}"

# Remove old zip if exists
rm -f lambda_function.zip

# Create new zip
zip lambda_function.zip lambda_function.py
echo -e "${GREEN}   Lambda function packaged${NC}"

echo -e "${YELLOW}Step 6: Deploying infrastructure...${NC}"

# Initialize Terraform
terraform init

# Plan deployment
echo "   Running terraform plan..."
terraform plan

# Ask for confirmation
echo ""
read -p "Do you want to apply these changes? (y/N): " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "   Applying changes..."
    terraform apply -auto-approve
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ Deployment successful!${NC}"
        echo ""
        
        # Display outputs
        echo -e "${BLUE}=== DEPLOYMENT OUTPUTS ===${NC}"
        terraform output
        
        echo ""
        echo -e "${BLUE}=== TESTING ===${NC}"
        echo "You can now test the API using:"
        echo "  ./test-api-enhanced.sh"
        echo ""
        echo "Or manually test the health endpoint:"
        API_BASE_URL=$(terraform output -raw api_gateway_base_url 2>/dev/null)
        if [ ! -z "$API_BASE_URL" ]; then
            echo "  curl -X GET $API_BASE_URL/api/health"
        fi
        
    else
        echo -e "${RED}❌ Deployment failed${NC}"
        exit 1
    fi
else
    echo "Deployment cancelled."
fi

echo ""
echo -e "${GREEN}Enhanced API Gateway deployment completed!${NC}"
echo ""
echo -e "${BLUE}Final file structure:${NC}"
echo "  main.tf (integrated - all infrastructure)"
echo "  outputs.tf (integrated - all outputs)"  
echo "  variables.tf (unchanged)"
echo "  lambda_function.py (enhanced)"
echo ""
echo -e "${BLUE}Backup files created:${NC}"
echo "  main.tf.backup"
echo "  outputs.tf.backup"
echo "  lambda_function.py.backup"
echo "  api-gateway-enhanced.tf.backup"
echo "  outputs-enhanced.tf.backup"