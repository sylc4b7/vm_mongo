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

# Private Subnet (CHANGED: No public IP)
resource "aws_subnet" "main" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = false  # CHANGED: No public IP
  
  tags = {
    Name = "mongo-private-subnet"
  }
}

# REMOVED: Internet Gateway, Route Table (no longer needed)

# Security Groups
resource "aws_security_group" "ec2" {
  name_prefix = "mongo-ec2-"
  vpc_id      = aws_vpc.main.id
  
  # REMOVED: SSH ingress rule (no public access)
  
  ingress {
    from_port       = 27017
    to_port         = 27017
    protocol        = "tcp"
    security_groups = [aws_security_group.lambda.id]
  }
  
  # REMOVED: Outbound rules (no internet needed)
}

resource "aws_security_group" "lambda" {
  name_prefix = "mongo-lambda-"
  vpc_id      = aws_vpc.main.id
  
  egress {
    from_port   = 27017
    to_port     = 27017
    protocol    = "tcp"
    security_groups = [aws_security_group.ec2.id]
  }
}

# REMOVED: Key Pair (no SSH access)

# EC2 Instance
resource "aws_instance" "mongo" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t2.micro"
  vpc_security_group_ids = [aws_security_group.ec2.id]
  subnet_id             = aws_subnet.main.id
  
  # REMOVED: key_name and user_data (already installed)
  
  tags = {
    Name = "mongo-server-private"
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