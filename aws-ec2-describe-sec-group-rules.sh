#!/bin/sh
# Creates a TSV of SecurityGroupID, 
aws ec2 describe-security-groups \
    | jq -cer '.SecurityGroups[].IpPermissions[] | ( [ (.FromPort | tostring), (.ToPort | tostring), .IpProtocol, .IpRanges[].CidrIp ] ) | @tsv'
