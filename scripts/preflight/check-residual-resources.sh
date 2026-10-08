#!/usr/bin/env bash
set -euo pipefail

: "${PROJECT_NAME:=oficina-dgcar}"
: "${TARGET_ENVIRONMENT:=homolog}"
: "${VPC_CIDR:=10.40.0.0/16}"
: "${EXPECTED_SUBNET_CIDRS:=10.40.1.0/24 10.40.2.0/24 10.40.11.0/24 10.40.12.0/24}"
: "${TF_DIR:=terraform}"

state_has_resource() {
  local address="$1"
  terraform -chdir="$TF_DIR" state show "$address" >/dev/null 2>&1
}

vpcs="$(aws ec2 describe-vpcs \
  --filters "Name=cidr,Values=${VPC_CIDR}" \
  --query "Vpcs[].VpcId" \
  --output text)"

if [ -n "$vpcs" ] && ! state_has_resource aws_vpc.main; then
  echo "VPC residual encontrada fora do state."
  echo "CIDR: $VPC_CIDR"
  echo "VPCs: $vpcs"
  echo "Saneie o state ou remova o ambiente residual antes do provisionamento."
  exit 1
fi

index=0
for cidr in $EXPECTED_SUBNET_CIDRS; do
  if [ "$index" -lt 2 ]; then
    subnet_address="aws_subnet.public[$index]"
  else
    subnet_address="aws_subnet.private[$((index - 2))]"
  fi

  subnets="$(aws ec2 describe-subnets \
    --filters "Name=cidr-block,Values=${cidr}" \
    --query "Subnets[].SubnetId" \
    --output text)"

  if [ -n "$subnets" ] && ! state_has_resource "$subnet_address"; then
    echo "Subnet residual encontrada fora do state."
    echo "CIDR: $cidr"
    echo "Subnets: $subnets"
    echo "Endereco Terraform esperado: $subnet_address"
    exit 1
  fi

  index=$((index + 1))
done

echo "Recursos residuais conflitantes nao encontrados."
