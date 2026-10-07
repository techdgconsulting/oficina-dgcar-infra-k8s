#!/usr/bin/env bash
set -euo pipefail

failures=0

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

check_empty "EKS" "aws eks list-clusters --query \"clusters[?contains(@, 'oficina-dgcar')]\" --output text"
check_empty "API Gateway" "aws apigatewayv2 get-apis --query \"Items[?contains(Name, 'oficina-dgcar')].ApiId\" --output text"
check_empty "ECR" "aws ecr describe-repositories --query \"repositories[?contains(repositoryName, 'oficina-dgcar')].repositoryName\" --output text 2>/dev/null || true"
check_empty "VPC" "aws ec2 describe-vpcs --filters \"Name=tag:Project,Values=oficina-dgcar\" --query \"Vpcs[].VpcId\" --output text"
check_empty "RDS" "aws rds describe-db-instances --query \"DBInstances[?contains(DBInstanceIdentifier, 'oficina-dgcar')].DBInstanceIdentifier\" --output text"
check_empty "Lambda" "aws lambda list-functions --query \"Functions[?contains(FunctionName, 'oficina-dgcar')].FunctionName\" --output text"

if [ "$failures" -gt 0 ]; then
  exit 1
fi

echo "Ambiente homolog removido."
