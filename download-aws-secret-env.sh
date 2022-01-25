#!/usr/bin/env bash
# download-aws-secret-env.sh v0.2
[ "${DEBUG:-0}" = "1" ] && set -x


################################################################################
### Functions    

_get_aws_tags () {

    # Try to get data from ECS, then from EC2, metadata
    DATA="$(_get_ecs_tags)"
    DATA="${DATA:-$(_get_ec2_tags)}"
    [ -z "$DATA" ] && echo "$0: No AWS tags found" >&2 && return 0

    # Print tags (replacing ':' chars before a '=' char with a '_' char) as AWS_TAG_$key=$value
    _TMP="$(mktemp)"
    printf "%s\n" "$DATA" | sed -r 's/TAGS\t(.*)\t.*\t.*\t(.*)/\1="\2"/' \
        | sed -e 's/^\([^=]\+\):\([^=]\+\)=/\1_\2=/g; s/^\([^=]\+\):\([^=]\+\)=/\1_\2=/g; s/^/AWS_TAG_/' \
        | grep -v '^AWS_TAG_aws_' \
        > "$_TMP"

    set -a ;  . "$_TMP" ;  set +a
    rm -f "$_TMP"

    # If a tag named "Secrets_Region" is on this instance, use that value as the region to query secrets from.
    # Otherwise default to the current region.
    AWS_SECRETS_REGION="${AWS_TAG_Secrets_Region:-$AWS_DEFAULT_REGION}"

    # Add 'Load_Secrets' tag to AWS_SECRETS_IDS array
    [ -n "$AWS_TAG_Load_Secrets" ] && AWS_SECRETS_IDS+=($AWS_TAG_Load_Secrets)
}
_get_ec2_tags () {
    EC2_INSTANCE_ID="${EC2_INSTANCE_ID:-$(curl -s 169.254.169.254/latest/meta-data/instance-id)}"
    [ -z "$EC2_INSTANCE_ID" ] && return 0
    aws ec2 describe-tags --filter Name=resource-id,Values="$EC2_INSTANCE_ID" --output text || \
        _no_tags_err "EC2 instance '$EC2_INSTANCE_ID'"
}
_get_ecs_tags () {
    ECS_TASK_ARN="${ECS_TASK_ARN:-$(curl -s 169.254.170.2/v2/metadata | jq -r .TaskARN)}"
    [ -z "$ECS_TASK_ARN" ] && return 0
    aws ecs list-tags-for-resource --resource-arn "$ECS_TASK_ARN" --output text || \
        _no_tags_err "ECS task '$ECS_TASK_ARN'"
}
_no_tags_err () { echo "$0: Error: could not pull tags from " "$@" >&2 ; exit 1 ; }
_cleanup () { [ -n "$_TMP" ] && rm -rf "$_TMP" ; } ; trap _cleanup EXIT

_get_aws_secrets () {
    [ ${#AWS_SECRETS_IDS[@]} -lt 1 ] && echo "$0: Error: no Secret IDs found" >&2 && exit 1

    # Truncate file and lock down permissions
    cat /dev/null > "$SECRETS_FILE"
    chmod 0600 "$SECRETS_FILE"

    fail=0
    declare -a aws_secrets_opts=()
    [ -n "$AWS_SECRETS_REGION" ] && aws_secrets_opts+=("--region" "$AWS_SECRETS_REGION")

    # The tag 'Load_Secrets' should contain a space-separated list of secret IDs to retrieve.
    for secret in "${AWS_SECRETS_IDS[@]}" ; do
        DATA="$( aws "${aws_secrets_opts[@]}" secretsmanager get-secret-value \
                    --query SecretString --version-stage AWSCURRENT \
                    --output text --secret-id "$secret" )"
        if [ $? -ne 0 ] ; then
            echo "$0: Warning: Could not retrieve AWS Secrets Manager secret id '$secret'" >&2
            fail=1
        fi

        # If first character (after whitespace) is "{", assume this is a JSON map/dict
        if [ "$(printf "%s\n" "$DATA" | sed -e 's/^[[:space:]]//g' | cut -b 1)" = "{" ] ; then
            printf "%s\n" "$DATA" | jq -r "to_entries|map(\"\(.key)='\(.value|tostring)'\")|.[]" >> "$SECRETS_FILE"

        # Otherwise assume the secret is plaintext (not JSON)
        else
            printf "%s\n" "$DATA" >> "$SECRETS_FILE"
        fi
    done

    # Load secrets as environment vars and export them
    if [ -s "$SECRETS_FILE" ] ; then
        set -a
        . "$SECRETS_FILE"
        set +a
    fi

    [ $fail -eq 1 ] && exit 1
}

_usage () {
    cat <<EOUSAGE
Usage: $0 [OPTIONS] [ARGS [..]]

Downloads AWS Secrets Manager secrets and stores them in '\$HOME/.secrets'
(converting JSON dicts into key=value pairs), then executes any command-line
arguments after loading the '.secrets' file into the current shell session (to
set enironment variables).

Options:
    -R REGION               AWS region to use for getting EC2 tags
    -S REGION               AWS region to use for Secrets Manager
    -I INSTANCE_ID          An EC2 Instance ID to load tags from
    -i SECRET_ID            An AWS Secrets Manager ID to query; value must be a JSON object.
                            You can specify this option multiple times.
    -s FILE                 A file to store the secrets in key=value format
    -j                      Treat secret value as a JSON dict

The following environment variables are detected:
    SECRETS_FILE                Same as '-s' option
    AWS_DEFAULT_REGION          Default if '-R' and EC2 metadata do not find the region
    AWS_SECRETS_REGION          Same as '-S' option
    EC2_INSTANCE_ID             An EC2 instance to retrieve tags from. If not found,
                                checks EC2 metadata for current instance id. A tag
                                'Secrets_Region' becomes the default '-S' option. A tag
                                'Load_Secrets' adds to the '-i' option.

Any ARGS found will be executed after the secrets have been exported.

Example:
  $ download-aws-secret-env.sh /bin/sh -c 'echo \$SECRET_KEY'
EOUSAGE
    exit 1
}

################################################################################
### Options    

declare -a AWS_SECRETS_IDS=()
while getopts "R:S:I:i:s:jh" args ; do
    case $args in
        R)
            AWS_DEFAULT_REGION="$OPTARG" ;;
        S)
            AWS_SECRETS_REGION="$OPTARG" ;;
        I)
            EC2_INSTANCE_ID="$OPTARG" ;;
        i)
            AWS_SECRETS_IDS+=("$OPTARG") ;;
        s)
            SECRETS_FILE="$OPTARG" ;;
        h)
            _usage ;;
        *)
            _usage ;;
    esac
done
shift $(($OPTIND-1))

################################################################################
### Variables  

# If AWS_DEFAULT_REGION was not set, try to get the region from either ECS or EC2 metadata
AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-$(curl -s 169.254.170.2/v2/metadata | jq -r .TaskARN | cut -d : -f 4)}"
AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-$(curl -s 169.254.169.254/latest/meta-data/placement/availability-zone  | sed -e "s/.$//")}"
[ -n "$AWS_DEFAULT_REGION" ] && export AWS_DEFAULT_REGION

# Set HOME if it's not already set
export HOME="${HOME:-$(getent passwd "$(id -u -n)" | cut -d : -f 6)}"

# If SECRETS_FILE was not set, default to $HOME/.secrets
SECRETS_FILE="${SECRETS_FILE:-$HOME/.secrets}"

###############################################################################
### Main   

_get_aws_tags
_get_aws_secrets

# If there were command-line arguments, execute them
if [ $# -gt 0 ] ; then
    exec "$@"

# Otherwise just print the path to the secrets file
else
    echo "$SECRETS_FILE"
    exit 0
fi
