#!/usr/bin/env bash
set -euo pipefail

: "${TF_STATE_BUCKET:?TF_STATE_BUCKET nao informado}"
: "${TF_STATE_KEY:?TF_STATE_KEY nao informado}"

lock_key="${TF_STATE_KEY}.tflock"

if aws s3api head-object --bucket "$TF_STATE_BUCKET" --key "$lock_key" >/dev/null 2>&1; then
  echo "Lock Terraform ativo encontrado."
  echo "Bucket: $TF_STATE_BUCKET"
  echo "Key: $lock_key"
  echo "Inspecione com:"
  echo "aws s3api get-object --bucket $TF_STATE_BUCKET --key $lock_key lock.json"
  exit 1
fi

echo "Lock Terraform ausente."
