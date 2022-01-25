#!/bin/sh
set -eu
aws ec2 describe-instances | jq -r '.Reservations[].Instances[].SecurityGroups[].GroupId' | sort -u
