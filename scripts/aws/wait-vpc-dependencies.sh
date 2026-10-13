#!/usr/bin/env bash
set -euo pipefail

vpc_id="${1:?VPC nao informada}"

for attempt in $(seq 1 30); do
  eni_count="$(aws ec2 describe-network-interfaces \
    --filters "Name=vpc-id,Values=${vpc_id}" \
    --query "length(NetworkInterfaces[?contains(Description, 'Lambda') || contains(Description, 'RDS') || contains(Description, 'ELB') || contains(Description, 'Elastic Load Balancing')])" \
    --output text)"

  lb_count="$(aws elbv2 describe-load-balancers \
    --query "length(LoadBalancers[?VpcId=='${vpc_id}'])" \
    --output text)"

  if [ "$eni_count" = "0" ] && [ "$lb_count" = "0" ]; then
    echo "Dependencias externas da VPC liberadas."
    exit 0
  fi

  echo "Aguardando dependencias externas da VPC: ENIs Lambda/RDS/LB=$eni_count, LoadBalancers=$lb_count, tentativa $attempt/30"
  sleep 20
done

echo "Dependencias externas ainda presas na VPC $vpc_id."
scripts/preflight/check-vpc-dependencies.sh "$vpc_id"
exit 1
