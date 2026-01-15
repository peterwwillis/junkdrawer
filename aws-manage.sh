#!/usr/bin/env bash
set -eu
[ "${DEBUG:-0}" = "1" ] && set -x

_errexit () { echo "Error: $*" 1>&2 ; exit 1 ; }
_stderrlog () { echo "$*" 1>&2 ; }

_cmd_list_keypairs () {

    declare -A keypairs

    for aws_profile_name in $( aws-sso list --csv | cut -d , -f 4 ) ; do
        _stderrlog "Getting AWS key pairs from AWS profile $aws_profile_name ..."
        acct_id="$( aws-sso list --csv | grep -E "^[0-9]+,[^,]+,[^,]+,${aws_profile_name}," | cut -d , -f 1 )"
        keypairs["$acct_id"]="$( aws --profile "$aws_profile_name" ec2 describe-key-pairs --query 'KeyPairs[*].KeyName' --output text | tr '\t' '\n' )"
    done

    echo "AWSAccountID,KeyPair"
    for acct_id in "${!keypairs[@]}" ; do
        for keypair in ${keypairs[$acct_id]} ; do
            printf "%s,%s\n" "${acct_id}" "${keypair}"
        done
    done

}

_cmd_list_users () {

    # Loop over profiles from aws-sso
    declare -A iam_users sso_users

    # Get IAM users from all AWS profiles
    for aws_profile_name in $(aws-sso list --csv | cut -d , -f 4) ; do
        _stderrlog "Getting IAM users from AWS profile $aws_profile_name ..."
        acct_id="$( aws-sso list --csv | grep -E "^[0-9]+,[^,]+,[^,]+,${aws_profile_name}," | cut -d , -f 1 )"
        iam_users["$acct_id"]="$( aws --profile "$aws_profile_name" iam list-users --query 'Users[*].UserName' --output text | tr '\t' '\n' )"
    done

    # Get SSO users from each AWS SSO store
    for aws_sso_store_id in $(aws sso-admin list-instances --query 'Instances[*].IdentityStoreId' --output text); do
      _stderrlog "Getting SSO users from SSO Identity Store $aws_sso_store_id ..."
      sso_users["$aws_sso_store_id"]="$( aws identitystore list-users --identity-store-id "$aws_sso_store_id" --query 'Users[*].UserName' --output text )"
    done

    echo "AWSAccountID,SSOStoreID,UserName"
    for acct_id in "${!iam_users[@]}" ; do
        for user in ${iam_users[$acct_id]} ; do
            printf "%s,,%s\n" "${acct_id}" "${user}"
        done
    done
    for store_id in "${!sso_users[@]}" ; do
        for user in ${sso_users[$store_id]} ; do
            printf ",%s,%s\n" "${store_id}" "${user}"
        done
    done

}

_cmd_list_public_ips () {

    declare -a public_ip_map

    for aws_profile_name in $( aws-sso list --csv | cut -d , -f 4 ) ; do
        _stderrlog "Getting IPs from AWS profile $aws_profile_name ..."
        acct_id="$( aws-sso list --csv | grep -E "^[0-9]+,[^,]+,[^,]+,${aws_profile_name}," | cut -d , -f 1 )"

        # Get all AWS regions
        regions="$(aws --profile "$aws_profile_name" ec2 describe-regions --query 'Regions[*].RegionName' --output text)"
        for region in $regions; do
            _stderrlog "Checking region $region ..."

            _stderrlog "Checking EC2 instances with public IPs ..."
            for ip in $( aws ec2 describe-instances --profile "$aws_profile_name" --region "$region" --query 'Reservations[*].Instances[*].PublicIpAddress' --output text ) ; do
                public_ip_map+=("${acct_id},${region},EC2PublicIP,${ip}")
            done

            _stderrlog "Checking Elastic IPs ..."
            for ip in $( aws ec2 describe-addresses --profile "$aws_profile_name" --region "$region" --query 'Addresses[*].PublicIp' --output text ) ; do
                public_ip_map+=("${acct_id},${region},ElasticIP,${ip}")
            done

            _stderrlog "Checking NAT Gateway IPs ..."
            for ip in $( aws ec2 describe-nat-gateways --profile "$aws_profile_name" --region "$region" --query 'NatGateways[*].NatGatewayAddresses[*].PublicIp' --output text ) ; do
                public_ip_map+=("${acct_id},${region},NATGatewayIP,${ip}")
            done
        done
    done

    echo "AWSAccountID,Region,ServiceType,IP"

    for row in "${public_ip_map[@]}" ; do
        printf "%s\n" "$row"
    done

}


#       Deletes the specified IAM user. Unlike the Amazon Web Services
#       Management Console, when you delete a user programmatically, you must
#       delete the items attached to the user manually, or the deletion fails.
#       For more information, see Deleting an IAM user . Before attempting to
#       delete a user, remove the following items:
#
#       o Password ( DeleteLoginProfile )
#       o Access keys ( DeleteAccessKey )
#       o Signing certificate ( DeleteSigningCertificate )
#       o SSH public key ( DeleteSSHPublicKey )
#       o Git credentials ( DeleteServiceSpecificCredential )
#       o Multi-factor authentication (MFA) device ( DeactivateMFADevice ,
#         DeleteVirtualMFADevice )
#       o Inline policies ( DeleteUserPolicy )
#       o Attached managed policies ( DetachUserPolicy )
_cmd_delete_iam_user () {
    local acct_id="$1" username="$2"

    # Find the AWS profile matching the account ID
    aws_profile_name="$( aws-sso list --csv | grep -E "^${acct_id}," | cut -d , -f 4 )"
    aws --profile "$aws_profile_name" iam delete-user --user-name "$username"
    
}

_cmd_add_iam_user () {
    local acct_id="${1:-}" username="${2:-}" aws_profile_name
    if [ -z "$acct_id" ] || [ -z "$username" ] ; then
        _errexit "Pass an account ID and username"
    fi

    aws_profile_name="$( aws-sso list --csv | grep -E "^${acct_id}," | cut -d , -f 4 )"
    [ -n "$aws_profile_name" ] || _errexit "AWS profile name not found"

    echo "Creating IAM user: $username ..."
    aws --profile "$aws_profile_name" iam get-user --user-name "$username" 2>/dev/null 1>/dev/null || \
        aws --profile "$aws_profile_name" iam create-user --user-name "$username" >/dev/null

    declare -a policies=(
        "arn:aws:iam::aws:policy/IAMUserChangePassword"
        "arn:aws:iam::$acct_id:policy/AllowAttachMFAToOwnIAMUser"
    )

    for policy_arn in "${policies[@]}"; do
        if ! _is_policy_attached "$aws_profile_name" "$username" "$policy_arn" ; then
            echo "Attaching policy: $policy_arn"
            aws --profile "$aws_profile_name" iam attach-user-policy \
                --user-name "$username" --policy-arn "$policy_arn" >/dev/null
        fi
    done

    echo "Setting AWS Console password ..."
    random_pw="$( LC_ALL=C tr -dc 'a-zA-Z0-9-_\$' </dev/urandom | fold -w 20 | sed 1q )"
    if aws --profile "$aws_profile_name" iam get-login-profile --user-name "$username" 2>/dev/null 1>/dev/null ; then
        aws --profile "$aws_profile_name" iam update-login-profile \
          --user-name "$username" --password "$random_pw" --password-reset-required
    else
        aws --profile "$aws_profile_name" iam create-login-profile \
          --user-name "$username" --password "$random_pw" --password-reset-required
    fi

    echo ""
    echo "Below are the login credentials for user $username in account $acct_id. Please copy them into"
    echo "a new 1Password entry."
    echo "Login URL: https://$acct_id.signin.aws.amazon.com/console"
    echo "Username: $username"
    echo "Password: $random_pw"
    echo ""
}

_cmd_attach_iam_user_policy () {
    local acct_id="${1:-}" username="${2:-}" policy_name="${3:-}" aws_profile_name
    if [ -z "$acct_id" ] || [ -z "$username" ] || [ -z "$policy_name" ] ; then
        _errexit "Pass an account ID, username, and policy name"
    fi

    aws_profile_name="$( aws-sso list --csv | grep -E "^${acct_id}," | cut -d , -f 4 )"
    [ -n "$aws_profile_name" ] || _errexit "AWS profile name not found"

    policy_arn=''
    if aws --profile "$aws_profile_name" iam get-policy \
        --policy-arn "arn:aws:iam::aws:policy/$policy_name" 2>/dev/null 1>/dev/null
    then
        policy_arn="arn:aws:iam::aws:policy/$policy_name"
    else
        policy_arn="arn:aws:iam::aws:policy/$policy_name"
    fi

    echo "Attaching policy $policy_arn to username $username in account $acct_id ..."
    aws --profile "$aws_profile_name" iam attach-user-policy --user-name "$username" --policy-arn "$policy_arn"
}

_is_policy_attached () {
  local aws_profile_name="$1" user="$2" policy_arn="$3"
  aws --profile "$aws_profile_name" iam list-attached-user-policies --user-name "$user" \
      --query "AttachedPolicies[?PolicyArn=='$policy_arn']" --output text \
    | grep -q "$policy_arn"
}


_usage () {
    cat <<EOUSAGE
Usage: $0 COMMAND [ARGS ..]

Script to make managing AWS accounts easier.

(Note: this script is designed to work using AWS profiles generated by the \`aws-sso\` tool)


Commands:

    list_users                              List all users (IAM & SSO), output as a CSV file
    list_keypairs                           List all EC2 keypairs (used to SSH into instances)
    list_public_ips                         List all Public IPs in all accounts and regions
    add_iam_user ACCOUNTID USER             Create an IAM user USERNAME in account ACCOUNTID
    attach_iam_user_policy ACCOUNTID USER POLICYNAME
                                            Attach policy POLICYNAME to USER in ACCOUNTID.
                                            (must be a managed or customer policy, not inline)
    delete_iam_user ACCOUNTID USER          Delete a single IAM user
    help                                    This screen (usage)
EOUSAGE
    exit 1
}

[ $# -gt 0 ] || _usage

cmd="$1"; shift
if [ "$cmd" = "-h" ] || [ "$cmd" = "--help" ] || [ "$cmd" = "help" ] ; then
    _usage
else
    _cmd_"$cmd" "$@"
fi
