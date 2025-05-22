#!/usr/bin/env bash
# terraform-list-all-resources-state-id.sh - List every 'id' attribute of every managed resource in a Terraform state
set -eu
[ "${DEBUG:-0}" = "1" ] && set -x

TERRAFORM_CMD="${TERRAFORM_CMD:-terraformsh}"

declare -A resource_ids=()

_process_state_resources () {
    local statefile="$1"
    local resource='' id=''

    local resource_regex='^# (.+):$'
    local id_regex='^[[:space:]]+id[[:space:]]+= (.*)$'

    while IFS= read -r line ; do

            if [[ $line =~ $resource_regex ]] ; then

                if [ -n "$id" ] && [ -n "$resource" ] ; then
                    resource_ids["$resource"]="$id"
                    id=''
                fi

                resource="${BASH_REMATCH[1]}"

            elif [[ $line =~ $id_regex ]] ; then
                id="${BASH_REMATCH[1]}"
            fi

        done < <(INIT_ARGS="-backend=false" $TERRAFORM_CMD show "$statefile")
}


$TERRAFORM_CMD state pull > "$(pwd)/current.tfstate"
_process_state_resources "$(pwd)/current.tfstate"

for key in "${!resource_ids[@]}" ; do
    echo "key $key id ${resource_ids[$key]}"
done

