#!/usr/bin/env sh
# aws-ec2-get-running-instances.sh - Get the Instance ID, key name, group ID, and public IP of running AWS EC2 instances

aws ec2 describe-instances --query 'Reservations[*].Instances[*].[InstanceId,KeyName,SecurityGroups[*].GroupId,PublicIpAddress]' --filters Name=instance-state-name,Values=running "$@" | jq -cer .[][]
