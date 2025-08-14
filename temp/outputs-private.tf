output "ec2_private_ip" {
  description = "Private IP of EC2 instance"
  value       = aws_instance.mongo.private_ip
}

output "lambda_function_name" {
  description = "Lambda function name"
  value       = aws_lambda_function.mongo_client.function_name
}

# REMOVED: ec2_public_ip (no longer exists)