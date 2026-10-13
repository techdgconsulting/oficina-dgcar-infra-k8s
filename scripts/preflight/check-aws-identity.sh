#!/usr/bin/env bash
set -euo pipefail

account_id="$(aws sts get-caller-identity --query Account --output text)"
arn="$(aws sts get-caller-identity --query Arn --output text)"
region="${AWS_REGION:-$(aws configure get region)}"

if [ -z "$account_id" ] || [ "$account_id" = "None" ]; then
  echo "Conta AWS nao resolvida."
  exit 1
fi

if [ -z "$region" ] || [ "$region" = "None" ]; then
  echo "Regiao AWS nao resolvida."
  exit 1
fi

echo "AWS account: $account_id"
echo "AWS principal: $arn"
echo "AWS region: $region"
