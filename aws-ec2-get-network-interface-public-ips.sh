#!/usr/bin/env sh
# aws-ec2-get-network-interface-public-ips.sh - Get the public IP of AWS EC2 network interfaces

aws ec2 describe-network-interfaces --query 'NetworkInterfaces[*].Association.PublicIp' "$@" | jq -r .[]
