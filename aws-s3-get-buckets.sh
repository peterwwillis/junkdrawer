#!/bin/sh
set -e
aws s3api list-buckets --query "Buckets[].Name" | jq -r .[]
