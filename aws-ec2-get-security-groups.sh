#!/usr/bin/env sh
# aws-ec2-get-security-groups.sh - Get AWS EC2 security groups

aws ec2 describe-security-groups --query 'SecurityGroups[*]' | jq -r .
