#!/usr/bin/env bash
set -euo pipefail

cluster_name="${1:?cluster EKS nao informado}"
principal_arn="${2:?principal ARN nao informado}"
policy_arn="arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

if aws eks describe-access-entry \
  --cluster-name "$cluster_name" \
  --principal-arn "$principal_arn" >/dev/null 2>&1; then
  echo "Access entry ja existe para $principal_arn em $cluster_name."
else
  echo "Criando access entry para $principal_arn em $cluster_name."
  aws eks create-access-entry \
    --cluster-name "$cluster_name" \
    --principal-arn "$principal_arn" \
    --type STANDARD >/dev/null
fi

for attempt in $(seq 1 12); do
  if aws eks describe-access-entry \
    --cluster-name "$cluster_name" \
    --principal-arn "$principal_arn" >/dev/null 2>&1; then
    break
  fi

  echo "Aguardando access entry ficar disponivel: tentativa $attempt/12"
  sleep 5
done

associated_count="$(aws eks list-associated-access-policies \
  --cluster-name "$cluster_name" \
  --principal-arn "$principal_arn" \
  --query "length(associatedAccessPolicies[?policyArn=='${policy_arn}'])" \
  --output text)"

if [ "$associated_count" != "0" ]; then
  echo "Policy $policy_arn ja associada a $principal_arn em $cluster_name."
  exit 0
fi

echo "Associando policy $policy_arn a $principal_arn em $cluster_name."
aws eks associate-access-policy \
  --cluster-name "$cluster_name" \
  --principal-arn "$principal_arn" \
  --policy-arn "$policy_arn" \
  --access-scope type=cluster >/dev/null

echo "Acesso EKS garantido para $principal_arn em $cluster_name."
