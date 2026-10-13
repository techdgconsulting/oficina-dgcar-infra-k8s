#!/usr/bin/env bash
set -euo pipefail

: "${AWS_REGION:?AWS_REGION nao informado}"
: "${EKS_CLUSTER_NAME:?EKS_CLUSTER_NAME nao informado}"
: "${EKS_NODEGROUP_NAME:?EKS_NODEGROUP_NAME nao informado}"

status="$(aws eks describe-nodegroup \
  --region "$AWS_REGION" \
  --cluster-name "$EKS_CLUSTER_NAME" \
  --nodegroup-name "$EKS_NODEGROUP_NAME" \
  --query 'nodegroup.status' \
  --output text 2>/dev/null || true)"

if [ -z "$status" ]; then
  echo "Node group anterior nao encontrado."
  exit 0
fi

if [ "$status" != "CREATE_FAILED" ]; then
  echo "Node group existente em estado $status."
  exit 0
fi

echo "Node group anterior ficou em CREATE_FAILED. Remocao iniciada antes do novo provisionamento."
aws eks delete-nodegroup \
  --region "$AWS_REGION" \
  --cluster-name "$EKS_CLUSTER_NAME" \
  --nodegroup-name "$EKS_NODEGROUP_NAME" >/dev/null

aws eks wait nodegroup-deleted \
  --region "$AWS_REGION" \
  --cluster-name "$EKS_CLUSTER_NAME" \
  --nodegroup-name "$EKS_NODEGROUP_NAME"

echo "Node group CREATE_FAILED removido."
