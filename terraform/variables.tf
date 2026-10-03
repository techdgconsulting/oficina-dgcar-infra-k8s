variable "aws_region" {
  description = "AWS region where the Kubernetes infrastructure will be created."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name used as a prefix for AWS resources."
  type        = string
  default     = "oficina-dgcar"
}

variable "environment" {
  description = "Environment name for tagging and naming."
  type        = string
  default     = "academic"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.40.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets used by EKS nodes and LoadBalancers."
  type        = list(string)
  default     = ["10.40.1.0/24", "10.40.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks reserved for private workloads and RDS subnet sharing."
  type        = list(string)
  default     = ["10.40.11.0/24", "10.40.12.0/24"]
}

variable "eks_cluster_version" {
  description = "Amazon EKS Kubernetes version. Use null to let AWS choose the current default supported version."
  type        = string
  default     = null
}

variable "node_instance_types" {
  description = "EC2 instance types for the EKS managed node group."
  type        = list(string)
  default     = ["t3.small"]
}

variable "node_desired_size" {
  description = "Desired number of EKS worker nodes."
  type        = number
  default     = 1
}

variable "node_min_size" {
  description = "Minimum number of EKS worker nodes."
  type        = number
  default     = 1
}

variable "node_max_size" {
  description = "Maximum number of EKS worker nodes."
  type        = number
  default     = 2
}

variable "node_disk_size" {
  description = "Disk size in GiB for each EKS worker node."
  type        = number
  default     = 20
}

variable "enable_github_actions_eks_access" {
  description = "Whether Terraform should configure IAM/EKS permissions for the GitHub Actions deployment user."
  type        = bool
  default     = false
}

variable "github_actions_iam_user_name" {
  description = "Existing IAM user name used by GitHub Actions to push images to ECR and deploy to EKS."
  type        = string
  default     = "github-actions-oficina-dgcar"
}

variable "enable_api_gateway" {
  description = "Whether to create the HTTP API Gateway entrypoint."
  type        = bool
  default     = true
}

variable "api_backend_url" {
  description = "Public or private HTTP endpoint that receives proxied application traffic from API Gateway."
  type        = string
  default     = null
}

variable "auth_lambda_invoke_arn" {
  description = "Invoke ARN of the CPF authentication Lambda, produced by oficina-dgcar-auth-lambda."
  type        = string
  default     = null
}

variable "auth_lambda_function_name" {
  description = "Function name of the CPF authentication Lambda for API Gateway invoke permission."
  type        = string
  default     = null
}

variable "api_gateway_allowed_origins" {
  description = "Allowed origins for API Gateway CORS."
  type        = list(string)
  default     = ["*"]
}

variable "api_gateway_throttle_burst_limit" {
  description = "API Gateway burst limit."
  type        = number
  default     = 100
}

variable "api_gateway_throttle_rate_limit" {
  description = "API Gateway rate limit per second."
  type        = number
  default     = 50
}
