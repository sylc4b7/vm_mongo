output "ec2_private_ip" {
  description = "Private IP of EC2 instance"
  value       = aws_instance.mongo.private_ip
}

output "lambda_function_name" {
  description = "Lambda function name"
  value       = aws_lambda_function.mongo_client.function_name
}

output "api_gateway_invoke_url" {
  description = "API Gateway invoke URL"
  value       = "https://${aws_api_gateway_rest_api.mongo_api.id}.execute-api.${var.aws_region}.amazonaws.com/prod/mongo"
}

output "s3_bucket_name" {
  description = "S3 bucket name for static website"
  value       = aws_s3_bucket.spa.bucket
}

output "s3_website_url" {
  description = "S3 website endpoint"
  value       = "http://${aws_s3_bucket_website_configuration.spa.website_endpoint}"
}

output "cloudfront_domain" {
  description = "CloudFront distribution domain"
  value       = aws_cloudfront_distribution.spa.domain_name
}

output "spa_url" {
  description = "Single Page Application URL (HTTPS)"
  value       = "https://${aws_cloudfront_distribution.spa.domain_name}"
}