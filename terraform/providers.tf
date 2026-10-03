provider "aws" {
  region = var.aws_region

  skip_credentials_validation = var.skip_aws_credentials_validation
  skip_metadata_api_check     = var.skip_aws_metadata_api_check
  skip_requesting_account_id  = var.skip_aws_requesting_account_id

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
      Repository  = "oficina-dgcar-infra-k8s"
    }
  }
}
