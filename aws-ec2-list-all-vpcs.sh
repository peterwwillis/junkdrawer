#!/usr/bin/env sh
# aws-ec2-list-all-vpcs.sh - Lists all AWS VPCs in all regions.
#
# If you have the aws-sso command installed, runs on every available SSO profile.

AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-east-1}"

_use_aws_sso () {
    aws_profiles="$(aws-sso list --csv | cut -d , -f 4)"
    for profile in $aws_profiles ; do
        eval $(aws-sso -L error --no-config-check eval -p "$profile")

        _list_all_regions
    done
}

_list_all_regions () {
    for region in $(aws --region "$AWS_DEFAULT_REGION" ec2 describe-regions --query 'Regions[].{Name:RegionName}' --output text)
    do
        _list_region "$region"
    done
}

_list_region () {
    region="$1"; shift
    aws --region "$region" ec2 describe-vpcs --output json \
        | jq --arg region "$region" \
            '.Vpcs[] | { "OwnerID": .OwnerId, "VpcId": .VpcId, "CidrBlock": .CidrBlock, "Name": ( .Tags[] | select(.Key == "Name") | .Value ) , "Region": $region }'
}

if command -v aws-sso >/dev/null ; then
    _use_aws_sso
else
    _list_all_regions
fi
