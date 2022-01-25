#!/bin/sh
aws ec2 describe-security-groups --query 'SecurityGroups[*]' | jq -r .
