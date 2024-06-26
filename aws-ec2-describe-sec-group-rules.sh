#!/usr/bin/env sh
# aws-ec2-describe-sec-group-rules.sh - Print a TSV of AWS EC2 security group rules

# Creates a TSV of SecurityGroupID, 
aws ec2 describe-security-groups \
    | jq -cer '.SecurityGroups[].IpPermissions[] | ( [ (.FromPort | tostring), (.ToPort | tostring), .IpProtocol, .IpRanges[].CidrIp ] ) | @tsv'
