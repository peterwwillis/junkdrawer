#!/usr/bin/env bash
# terraform-target-apply.sh - select which terraform changes to apply
#
# This script will run a 'terraform plan', look for changing resources,
# and prompt you for which of them you want to apply. It will then run a
# plan using -targets for each resource, and then apply that plan file.
#
# You can also pass a log file of output from Terraform, so you can
# skip the initial plan run.
#
# You can also use a dry-run to step through the prompts and output the
# Terraform commands that would do what you want.

set -eu
[ "${DEBUG:-0}" = "1" ] && set -x

SA_TERRAFORM="${SA_TERRAFORM:-terraform}"

declare -A changes=() changetypes=() colorlesschanges=() tochange=()

_errexit () { printf "$0: $*" 1>&2 ; exit 1 ; }
_identify_changes () {
    local file="$1"; shift
    local stage=0 resource='' applytype='' colorlessfilecontent
    declare -a colorlesscontent=()

    colorlessfilecontent="$( cat "$file" | sed -r "s/\x1B\[([0-9]{1,3}(;[0-9]{1,2};?)?)?[mGK]//g" )"

    echo "$0: Identifying terraform changes in file '$file' ..."

    while IFS= read -r colorlessline ; do

        regex1='^[[:space:]]+# (.+) (will|must) be ([a-zA-Z0-9_-]+)'
        if [[ $colorlessline =~ $regex1 ]] ; then
            resource="${BASH_REMATCH[1]}"
            applytype="${BASH_REMATCH[3]}"
            stage=1
            [ $__opt_verbose -eq 0 ] || echo "$0: Detected resource '$resource', applytype '$applytype'"

        elif [ $stage -eq 1 ] ; then
            if [ "$colorlessline" = "" ] ; then
                changes["$resource"]="${colorlesscontent[@]}"
                colorlesschanges["$resource"]="${colorlesscontent[@]}"
                changetypes["$resource"]="$applytype"
                colorlesscontent=()
                stage=0
            else
                colorlesscontent+=("$colorlessline"$'\n') # Add newline to end of each entry
            fi
        fi
    done <<< "$colorlessfilecontent"
}

_prompt_dialog () {
    for resource in "${!colorlesschanges[@]}" ; do
        if [ ! "${changetypes[$resource]}" = "read" ] ; then
            outtext="
Resource:    $resource

${colorlesschanges[$resource]}
"
            if dialog --no-collapse --yesno "$outtext" 0 0 ; then # yes!
                tochange[$resource]="1"
            fi
        fi
    done
}

_prompt_text () {
    for resource in "${!changes[@]}" ; do
        if [ ! "${changetypes[$resource]}" = "read" ] ; then
            echo ""
            echo "$0: Resource to be changed: $resource"
            echo ""
            echo "$0: Changes proposed:"
            echo "${changes[$resource]}"
            echo ""
            read -r -p "$0: Target this resource? [y/N] " answer
            if [ "$answer" = "y" ] ; then
                tochange[$resource]="1"
            fi
        fi
    done

}

_main () {
    declare -a tf_opts=()
    local tmplogfile tmpplanfile

    if [ $# -lt 1 ] ; then
        echo "$0: No log file passed; running a Terraform plan to collect changes..."
        echo ""
        tmplogfile="$(mktemp)"
        $SA_TERRAFORM plan | tee "$tmplogfile"
        _identify_changes "$tmplogfile"
        rm -f "$tmplogfile"
    else
        for f in "$@" ; do
            _identify_changes "$f"
        done
    fi

    if command -v dialog 2>/dev/null ; then
        _prompt_dialog
    else
        _prompt_text
    fi

    if [ ${#tochange[@]} -lt 1 ] ; then
        echo "$0: No resources targeted; exiting..."
        return 0
    fi

    echo ""
    echo "$0: Ready to apply changes."
    echo "$0: Targeting the following resources: ${!tochange[*]}"
    echo ""
    echo "$0: Press enter to continue..."
    read -r answer

    for resource in "${!tochange[@]}" ; do
        tf_opts+=("-target=$resource")
    done

    set -x
    tmpplanfile="$(mktemp)"
    if [ $__opt_dryrun -eq 1 ] ; then
        echo + $SA_TERRAFORM plan "${tf_opts[@]}" -out="$tmpplanfile"
        echo + $SA_TERRAFORM apply "$tmpplanfile"
    else
        $SA_TERRAFORM plan "${tf_opts[@]}" -out="$tmpplanfile"
        $SA_TERRAFORM apply "$tmpplanfile"
    fi
    rm -f "$tmpplanfile"
    set +x
}

_usage () {
    cat <<EOUSAGE
Usage: $0 [OPTIONS] [LOGFILE [..]]

Takes a Terraform output log file, scans it for changing resources,
prompts the user which of the target resources they want to apply,
and then runs Terraform to apply those specific changes.

LOGFILE is the output of a 'terraform plan'. It can include colored
output or not.

If you do not pass LOGFILE, runs 'terraform plan' in the current
directory to generate output to look through.

Pass environment variable SA_TERRAFORM to specify the command to
use for Terraform (default: 'terraform').

Options:
  -T            Terraformsh mode. Sets USE_PLANFILE=0 and SA_TERRAFORM=terraformsh
  -N            Dry-run mode.
  -h            This output
  -v            Verbose mode

EOUSAGE
    exit 1
}

__opt_terraformsh=0 __opt_dryrun=0 __opt_verbose=0
while getopts "hTNv" args ; do
    case $args in
        h)  _usage ;;
        T)  __opt_terraformsh=1 ;;
        N)  __opt_dryrun=1 ;;
        v)  __opt_verbose=1 ;;
        *)  _errexit "Please pass correct _mktemp options" ;;
    esac
done
shift $(($OPTIND-1))

if [ $__opt_terraformsh -eq 1 ] ; then
    export USE_PLANFILE=0 SA_TERRAFORM="terraformsh"
fi

_main "$@"
