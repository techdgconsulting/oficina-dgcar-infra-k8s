#!/usr/bin/env bash
set -euo pipefail

failures=0
target_environment="${TARGET_ENVIRONMENT:-homolog}"
resource_prefix="oficina-dgcar-${target_environment}"
if [ "$target_environment" = "prod" ]; then
  ecr_repository_name="oficina-dgcar/prod-oficina-api"
else
  ecr_repository_name="oficina-dgcar/oficina-api"
fi

check_empty() {
  local label="$1"
  local command="$2"
  local result

  result="$(eval "$command")"
  if [ -n "$result" ]; then
    echo "Ainda existe recurso em $label:"
    echo "$result"
    failures=$((failures + 1))
  else
    echo "$label limpo."
  fi
}

check_empty "EKS" "aws eks list-clusters --query \"clusters[?contains(@, '${resource_prefix}')]\" --output text"
check_empty "API Gateway" "aws apigatewayv2 get-apis --query \"Items[?contains(Name, '${resource_prefix}')].ApiId\" --output text"
check_empty "ECR" "aws ecr describe-repositories --repository-names \"${ecr_repository_name}\" --query \"repositories[].repositoryName\" --output text 2>/dev/null || true"
check_empty "VPC" "aws ec2 describe-vpcs --filters \"Name=tag:Project,Values=oficina-dgcar\" \"Name=tag:Environment,Values=${target_environment}\" --query \"Vpcs[].VpcId\" --output text"
check_empty "RDS" "aws rds describe-db-instances --query \"DBInstances[?contains(DBInstanceIdentifier, '${resource_prefix}')].DBInstanceIdentifier\" --output text"
check_empty "Lambda" "aws lambda list-functions --query \"Functions[?contains(FunctionName, '${resource_prefix}')].FunctionName\" --output text"

if [ "$failures" -gt 0 ]; then
  exit 1
fi

echo "Ambiente ${target_environment} removido."
