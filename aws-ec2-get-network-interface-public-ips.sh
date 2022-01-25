#!/bin/sh
aws ec2 describe-network-interfaces --query 'NetworkInterfaces[*].Association.PublicIp' "$@" | jq -r .[]
