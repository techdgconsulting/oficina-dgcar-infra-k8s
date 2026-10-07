#!/usr/bin/env bash
set -euo pipefail

vpc_id="${1:-}"

if [ -z "$vpc_id" ]; then
  echo "VPC nao informada."
  exit 1
fi

echo "ENIs restantes na VPC $vpc_id"
aws ec2 describe-network-interfaces \
  --filters "Name=vpc-id,Values=${vpc_id}" \
  --query "NetworkInterfaces[*].{Id:NetworkInterfaceId,Status:Status,Description:Description,RequesterManaged:RequesterManaged,Subnet:SubnetId,Groups:Groups[*].GroupId}" \
  --output table

echo "Security groups restantes na VPC $vpc_id"
aws ec2 describe-security-groups \
  --filters "Name=vpc-id,Values=${vpc_id}" \
  --query "SecurityGroups[*].{Id:GroupId,Name:GroupName,Description:Description}" \
  --output table

echo "Load Balancers restantes na VPC $vpc_id"
aws elbv2 describe-load-balancers \
  --query "LoadBalancers[?VpcId=='${vpc_id}'].{Arn:LoadBalancerArn,Name:LoadBalancerName,State:State.Code}" \
  --output table

echo "VPC endpoints restantes na VPC $vpc_id"
aws ec2 describe-vpc-endpoints \
  --filters "Name=vpc-id,Values=${vpc_id}" \
  --query "VpcEndpoints[*].{Id:VpcEndpointId,State:State,Service:ServiceName}" \
  --output table
