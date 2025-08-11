# Phase 4: SPA + CDN + API Gateway + Private Backend
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

# S3 Bucket for Static Website
resource "aws_s3_bucket" "spa" {
  bucket = "mongo-spa-${random_string.bucket_suffix.result}"
}

resource "random_string" "bucket_suffix" {
  length  = 8
  special = false
  upper   = false
}

resource "aws_s3_bucket_website_configuration" "spa" {
  bucket = aws_s3_bucket.spa.id
  
  index_document {
    suffix = "index.html"
  }
  
  error_document {
    key = "index.html"
  }
}

resource "aws_s3_bucket_public_access_block" "spa" {
  bucket = aws_s3_bucket.spa.id
  
  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_policy" "spa" {
  bucket = aws_s3_bucket.spa.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadGetObject"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.spa.arn}/*"
      }
    ]
  })
}

# CloudFront Distribution
resource "aws_cloudfront_distribution" "spa" {
  origin {
    domain_name = aws_s3_bucket_website_configuration.spa.website_endpoint
    origin_id   = "S3-${aws_s3_bucket.spa.bucket}"
    
    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }
  
  enabled             = true
  default_root_object = "index.html"
  
  default_cache_behavior {
    allowed_methods        = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "S3-${aws_s3_bucket.spa.bucket}"
    compress               = true
    viewer_protocol_policy = "redirect-to-https"
    
    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
  }
  
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
  
  viewer_certificate {
    cloudfront_default_certificate = true
  }
  
  custom_error_response {
    error_code         = 404
    response_code      = 200
    response_page_path = "/index.html"
  }
}

# VPC (Private Backend - Same as Phase 3)
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
  
  tags = {
    Name = "mongo-vpc"
  }
}

resource "aws_subnet" "main" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = false
  
  tags = {
    Name = "mongo-private-subnet"
  }
}

# Security Groups
resource "aws_security_group" "ec2" {
  name_prefix = "mongo-ec2-"
  vpc_id      = aws_vpc.main.id
  
  ingress {
    from_port       = 27017
    to_port         = 27017
    protocol        = "tcp"
    security_groups = [aws_security_group.lambda.id]
  }
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

# EC2 Instance (Private)
resource "aws_instance" "mongo" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t2.micro"
  vpc_security_group_ids = [aws_security_group.ec2.id]
  subnet_id             = aws_subnet.main.id
  
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

# Lambda Layer
resource "aws_lambda_layer_version" "pymongo" {
  filename   = "pymongo-layer.zip"
  layer_name = "pymongo"
  
  compatible_runtimes = ["python3.9"]
}

# API Gateway
resource "aws_api_gateway_rest_api" "mongo_api" {
  name        = "mongo-api"
  description = "MongoDB API Gateway"
  
  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

resource "aws_api_gateway_resource" "mongo" {
  rest_api_id = aws_api_gateway_rest_api.mongo_api.id
  parent_id   = aws_api_gateway_rest_api.mongo_api.root_resource_id
  path_part   = "mongo"
}

resource "aws_api_gateway_method" "mongo_post" {
  rest_api_id   = aws_api_gateway_rest_api.mongo_api.id
  resource_id   = aws_api_gateway_resource.mongo.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "lambda" {
  rest_api_id = aws_api_gateway_rest_api.mongo_api.id
  resource_id = aws_api_gateway_resource.mongo.id
  http_method = aws_api_gateway_method.mongo_post.http_method
  
  integration_http_method = "POST"
  type                   = "AWS_PROXY"
  uri                    = aws_lambda_function.mongo_client.invoke_arn
}

resource "aws_lambda_permission" "api_gw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.mongo_client.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.mongo_api.execution_arn}/*/*"
}

resource "aws_api_gateway_deployment" "mongo_api" {
  depends_on = [
    aws_api_gateway_method.mongo_post,
    aws_api_gateway_integration.lambda,
  ]
  
  rest_api_id = aws_api_gateway_rest_api.mongo_api.id
  stage_name  = "prod"
}

# CORS Support
resource "aws_api_gateway_method" "mongo_options" {
  rest_api_id   = aws_api_gateway_rest_api.mongo_api.id
  resource_id   = aws_api_gateway_resource.mongo.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "mongo_options" {
  rest_api_id = aws_api_gateway_rest_api.mongo_api.id
  resource_id = aws_api_gateway_resource.mongo.id
  http_method = aws_api_gateway_method.mongo_options.http_method
  
  type = "MOCK"
  request_templates = {
    "application/json" = jsonencode({
      statusCode = 200
    })
  }
}

resource "aws_api_gateway_method_response" "mongo_options" {
  rest_api_id = aws_api_gateway_rest_api.mongo_api.id
  resource_id = aws_api_gateway_resource.mongo.id
  http_method = aws_api_gateway_method.mongo_options.http_method
  status_code = "200"
  
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_integration_response" "mongo_options" {
  rest_api_id = aws_api_gateway_rest_api.mongo_api.id
  resource_id = aws_api_gateway_resource.mongo.id
  http_method = aws_api_gateway_method.mongo_options.http_method
  status_code = aws_api_gateway_method_response.mongo_options.status_code
  
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'"
    "method.response.header.Access-Control-Allow-Methods" = "'GET,OPTIONS,POST,PUT'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
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