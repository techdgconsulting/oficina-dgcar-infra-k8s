variable "aws_region" {
  description = "AWS region where the Kubernetes infrastructure will be created."
  type        = string
  default     = "us-east-1"
}

variable "skip_aws_credentials_validation" {
  description = "Skip AWS credential validation during local and pull request plans."
  type        = bool
  default     = true
}

variable "skip_aws_metadata_api_check" {
  description = "Skip AWS metadata API checks during local and pull request plans."
  type        = bool
  default     = true
}

variable "skip_aws_requesting_account_id" {
  description = "Skip AWS account ID lookup during local and pull request plans."
  type        = bool
  default     = true
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

variable "availability_zones" {
  description = "Availability zones used by public and private subnets."
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
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

variable "enable_new_relic_kubernetes" {
  description = "Whether to install the New Relic Kubernetes integration through the official nri-bundle Helm chart."
  type        = bool
  default     = true
}

variable "new_relic_license_key" {
  description = "New Relic ingest license key used by the Kubernetes integration."
  type        = string
  default     = null
  sensitive   = true
}

variable "new_relic_namespace" {
  description = "Kubernetes namespace used by the New Relic Kubernetes integration."
  type        = string
  default     = "newrelic"
}

variable "new_relic_release_name" {
  description = "Helm release name for the New Relic Kubernetes integration."
  type        = string
  default     = "newrelic-bundle"
}

variable "new_relic_chart_version" {
  description = "Optional nri-bundle chart version. Null lets Helm use the latest chart available in the configured repository."
  type        = string
  default     = null
}

variable "enable_new_relic_observability" {
  description = "Whether to create New Relic dashboards and NRQL alert conditions for API, Kubernetes and business observability."
  type        = bool
  default     = true
}

variable "new_relic_account_id" {
  description = "New Relic account ID used to create dashboards and alert conditions."
  type        = number
  default     = null
}

variable "new_relic_api_key" {
  description = "New Relic User API Key used by Terraform to manage dashboards and alerts."
  type        = string
  default     = null
  sensitive   = true
}

variable "new_relic_region" {
  description = "New Relic API region. Use US for one.newrelic.com, EU for one.eu.newrelic.com or JP for one.jp.newrelic.com."
  type        = string
  default     = "US"
}

variable "new_relic_alert_p95_threshold_seconds" {
  description = "Critical threshold, in seconds, for the API p95 latency alert."
  type        = number
  default     = 2
}

variable "ecr_repository_name" {
  description = "ECR repository name for the application image. It must be unique per AWS account and region."
  type        = string
  default     = "oficina-dgcar/oficina-api"
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

variable "github_actions_iam_user_arn" {
  description = "Existing IAM user ARN used by GitHub Actions for optional EKS access entries."
  type        = string
  default     = null
}

variable "manage_github_actions_eks_access_entry" {
  description = "Whether Terraform should create an explicit EKS access entry for the GitHub Actions user. Keep false when the same principal creates the cluster and receives bootstrap admin access."
  type        = bool
  default     = false
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
