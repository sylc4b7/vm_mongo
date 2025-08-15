#!/bin/bash

echo "=== Enhanced MongoDB API Gateway Deployment ==="
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

# Step 1: Create enhanced main.tf
echo -e "${YELLOW}Step 1: Creating enhanced main.tf with API Gateway...${NC}"

# Backup existing main.tf
if [ -f "main.tf" ]; then
    cp main.tf main.tf.backup
    echo "   Backed up existing main.tf to main.tf.backup"
fi

# Create new main.tf with enhanced API Gateway
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

# Check if api-gateway-enhanced.tf exists and append it
if [ -f "api-gateway-enhanced.tf" ]; then
    cat api-gateway-enhanced.tf >> main.tf
    echo "   Appended API Gateway configuration"
else
    echo -e "${RED}Error: api-gateway-enhanced.tf not found${NC}"
    exit 1
fi

echo -e "${GREEN}   Enhanced main.tf created${NC}"

# Step 2: Update Lambda function
echo -e "${YELLOW}Step 2: Updating Lambda function...${NC}"

# Backup existing lambda function
if [ -f "lambda_function.py" ]; then
    cp lambda_function.py lambda_function.py.backup
    echo "   Backed up existing lambda_function.py"
fi

# Copy enhanced lambda function
cp lambda_function_enhanced.py lambda_function.py
echo -e "${GREEN}   Lambda function updated${NC}"

# Step 3: Update outputs
echo -e "${YELLOW}Step 3: Updating outputs...${NC}"

# Backup existing outputs
if [ -f "outputs.tf" ]; then
    cp outputs.tf outputs.tf.backup
    echo "   Backed up existing outputs.tf"
fi

# Copy enhanced outputs
cp outputs-enhanced.tf outputs.tf
echo -e "${GREEN}   Outputs updated${NC}"

# Step 4: Package Lambda function
echo -e "${YELLOW}Step 4: Packaging Lambda function...${NC}"

# Remove old zip if exists
rm -f lambda_function.zip

# Create new zip
zip lambda_function.zip lambda_function.py
echo -e "${GREEN}   Lambda function packaged${NC}"

# Step 5: Initialize and apply Terraform
echo -e "${YELLOW}Step 5: Deploying infrastructure...${NC}"

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
echo -e "${GREEN}Enhanced API Gateway deployment script completed!${NC}"