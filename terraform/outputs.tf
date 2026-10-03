output "aws_region" {
  description = "AWS region where resources were created."
  value       = var.aws_region
}

output "project_name" {
  description = "Project name used for resource naming."
  value       = var.project_name
}

output "vpc_id" {
  description = "Created VPC ID."
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "Public subnet IDs used by EKS nodes and external LoadBalancers."
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "Private subnet IDs shared with the database infrastructure."
  value       = aws_subnet.private[*].id
}

output "eks_cluster_security_group_id" {
  description = "EKS cluster security group allowed to access RDS."
  value       = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
}

output "ecr_repository_url" {
  description = "ECR repository URL for the application image."
  value       = aws_ecr_repository.app.repository_url
}

output "eks_cluster_name" {
  description = "EKS cluster name."
  value       = aws_eks_cluster.main.name
}

output "eks_cluster_endpoint" {
  description = "EKS API endpoint."
  value       = aws_eks_cluster.main.endpoint
}

output "github_actions_iam_user_arn" {
  description = "Expected IAM user ARN for the GitHub Actions deployment user when optional access automation is enabled."
  value       = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:user/${var.github_actions_iam_user_name}"
}

output "api_gateway_id" {
  description = "HTTP API Gateway ID."
  value       = var.enable_api_gateway ? aws_apigatewayv2_api.main[0].id : null
}

output "api_gateway_endpoint" {
  description = "HTTP API Gateway endpoint."
  value       = var.enable_api_gateway ? aws_apigatewayv2_api.main[0].api_endpoint : null
}

output "api_gateway_execution_arn" {
  description = "HTTP API Gateway execution ARN."
  value       = var.enable_api_gateway ? aws_apigatewayv2_api.main[0].execution_arn : null
}
