#!/usr/bin/env bash
set -euo pipefail

vpc_id="${1:?VPC nao informada}"

classic_lbs="$(aws elb describe-load-balancers \
  --query "LoadBalancerDescriptions[?VPCId=='${vpc_id}'].LoadBalancerName" \
  --output text)"

for lb_name in $classic_lbs; do
  echo "Removendo Classic Load Balancer: $lb_name"
  aws elb delete-load-balancer --load-balancer-name "$lb_name"
done

v2_lbs="$(aws elbv2 describe-load-balancers \
  --query "LoadBalancers[?VpcId=='${vpc_id}'].LoadBalancerArn" \
  --output text)"

for lb_arn in $v2_lbs; do
  echo "Removendo Load Balancer: $lb_arn"
  aws elbv2 delete-load-balancer --load-balancer-arn "$lb_arn"
done

echo "Load Balancers removidos ou ja ausentes."
