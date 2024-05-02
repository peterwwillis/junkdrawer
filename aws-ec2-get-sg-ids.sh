#!/usr/bin/env sh
# aws-ec2-get-sg-ids.sh - Get AWS EC2 instance security group IDs

set -eu
aws ec2 describe-instances | jq -r '.Reservations[].Instances[].SecurityGroups[].GroupId' | sort -u
