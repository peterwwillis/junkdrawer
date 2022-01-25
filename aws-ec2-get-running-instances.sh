#!/bin/sh
aws ec2 describe-instances --query 'Reservations[*].Instances[*].[InstanceId,KeyName,SecurityGroups[*].GroupId,PublicIpAddress]' --filters Name=instance-state-name,Values=running "$@" | jq -cer .[][]
