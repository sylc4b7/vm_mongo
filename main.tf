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
  source_code_hash = filebase64sha256("lambda_function.zip")
  
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
# Enhanced API Gateway with Multiple Endpoints
# This provides RESTful endpoints for testers

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
# GET /api/documents (find all)
resource "aws_api_gateway_method" "documents_get" {
  rest_api_id   = aws_api_gateway_rest_api.mongo_api.id
  resource_id   = aws_api_gateway_resource.documents.id
  http_method   = "GET"
  authorization = "NONE"
  api_key_required = true
}

# POST /api/documents (create)
resource "aws_api_gateway_method" "documents_post" {
  rest_api_id   = aws_api_gateway_rest_api.mongo_api.id
  resource_id   = aws_api_gateway_resource.documents.id
  http_method   = "POST"
  authorization = "NONE"
  api_key_required = true
}

# PUT /api/documents (update)
resource "aws_api_gateway_method" "documents_put" {
  rest_api_id   = aws_api_gateway_rest_api.mongo_api.id
  resource_id   = aws_api_gateway_resource.documents.id
  http_method   = "PUT"
  authorization = "NONE"
  api_key_required = true
}

# DELETE /api/documents (delete)
resource "aws_api_gateway_method" "documents_delete" {
  rest_api_id   = aws_api_gateway_rest_api.mongo_api.id
  resource_id   = aws_api_gateway_resource.documents.id
  http_method   = "DELETE"
  authorization = "NONE"
  api_key_required = true
}

# GET /api/health (health check)
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

# CORS Support for all methods
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

# CORS Integration
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

# CORS Method Responses
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

# CORS Integration Responses
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

# API Key for Authentication
resource "aws_api_gateway_api_key" "mongo_api_key" {
  name = "mongo-api-key"
}

# Usage Plan
resource "aws_api_gateway_usage_plan" "mongo_usage_plan" {
  name = "mongo-basic-plan"
  
  api_stages {
    api_id = aws_api_gateway_rest_api.mongo_api.id
    stage  = aws_api_gateway_deployment.mongo_api.stage_name
  }
  
  throttle_settings {
    rate_limit  = 100
    burst_limit = 200
  }
}

# Link API Key to Usage Plan
resource "aws_api_gateway_usage_plan_key" "mongo_usage_plan_key" {
  key_id        = aws_api_gateway_api_key.mongo_api_key.id
  key_type      = "API_KEY"
  usage_plan_id = aws_api_gateway_usage_plan.mongo_usage_plan.id
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