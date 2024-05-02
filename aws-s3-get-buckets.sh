#!/usr/bin/env sh
# aws-s3-get-buckets.sh - Get AWS S3 bucket names

set -e
aws s3api list-buckets --query "Buckets[].Name" | jq -r .[]
