output "ec2_private_ip" {
  description = "Private IP of EC2 instance"
  value       = aws_instance.mongo.private_ip
}

output "lambda_function_name" {
  description = "Lambda function name"
  value       = aws_lambda_function.mongo_client.function_name
}

output "api_gateway_url" {
  description = "API Gateway endpoint URL"
  value       = "${aws_api_gateway_rest_api.mongo_api.execution_arn}/prod/mongo"
}

output "api_gateway_invoke_url" {
  description = "API Gateway invoke URL for curl"
  value       = "https://${aws_api_gateway_rest_api.mongo_api.id}.execute-api.${var.aws_region}.amazonaws.com/prod/mongo"
}