#!/usr/bin/env sh
# aws-cli-cache-auth-keys.sh - Extract the auth keys from a cached AWS CLI authentication json file

if [ $# -lt 1 ] ; then
    echo "Usage: $0 ~/.aws/cli/cache/some-file.json"
    exit 1
fi

JSONFILE="$1"; shift

foo="$( cat "$JSONFILE" | jq -r '.Credentials |  [ "AWS_ACCESS_KEY_ID=" + (.AccessKeyId|@sh), "AWS_SECRET_ACCESS_KEY=" + (.SecretAccessKey|@sh), "AWS_SESSION_TOKEN=" + (.SessionToken|@sh) ] | .[]' ; echo "export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN" )"; eval "$foo"

# You don't want this in here if we set the above variables
unset AWS_PROFILE AWS_DEFAULT_PROFILE
