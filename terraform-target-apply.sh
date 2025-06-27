#!/usr/bin/env bash
# terraform-target-apply.sh - select which terraform changes to apply
#
# Uses 'terraform plan' output to detect changing resources, prompt a
# user which they want to apply, and apply them with -target option.

set -eu
[ "${DEBUG:-0}" = "1" ] && set -x

declare -A changes=() changetypes=() tochange=()

_errexit () { printf "$0: Error: %s\n" "$*" 1>&2 ; exit 1 ; }
_log () { printf "$0: Info: %s\n" "$*" 1>&2 ; }

# Usage: _identify_changes LOGFILE
# Looks through LOGFILE ('terraform plan' output) for changing resources.
# Populates global associative arrays:
#   - changes[resourcename]='changes_planned'
#   - colorlesschanges[resourcename]='changes_planned_color_stripped'
#   - changetypes[resourcename]='changetype' (replace, create, destroy)
_identify_changes () {
    local file="$1"; shift
    local stage=0 resource='' applytype=''
    declare -a content=()

    _log "Identifying terraform changes in file '$file' ..."

    while IFS= read -r line ; do

        #regex1='^[[:space:]]+# (.+) (will|must) be ([a-zA-Z0-9_-]+)'
        regex1=$'^\x1B\[[0-9;]*[a-zA-Z][[:space:]]+# (.+)\x1B\[[0-9;]*[a-zA-Z] (will|must) be ([a-zA-Z0-9_-]+)'
        if [[ $line =~ $regex1 ]] ; then
            resource="${BASH_REMATCH[1]}"
            applytype="${BASH_REMATCH[3]}"
            stage=1
            [ $__opt_verbose -eq 0 ] || _log "Detected resource '$resource', applytype '$applytype'"

        elif [ $stage -eq 1 ] ; then
            if [ "$line" = "" ] ; then
                changes["$resource"]="${content[*]}"
                changetypes["$resource"]="$applytype"
                content=()
                stage=0
            else
                content+=("$line"$'\n') # Add newline to end of each entry
            fi
        fi

    done <"$file"
}

# Loops over associative array 'changes'.
# Uses the `dialog` tool to prompt the user to accept or reject a change.
_prompt_dialog () {
    for resource in "${!changes[@]}" ; do
        if [ ! "${changetypes[$resource]}" = "read" ] ; then
            # 'dialog' program cannot output colored text. sigh...
            colorlesschange="$( printf "%s\n" "${changes[$resource]}" | sed -r "s/\x1B\[([0-9]{1,3}(;[0-9]{1,2};?)?)?[mGK]//g" )"
            outtext="
Resource:    $resource

$colorlesschange
"
            if dialog --no-collapse --yesno "$outtext" 0 0 ; then
                tochange[$resource]="1"
            fi
        fi
    done
}

# Loops over associative array 'changes'.
# Prompts the user to accept or reject a change.
_prompt_text () {
    for resource in "${!changes[@]}" ; do
        if [ ! "${changetypes[$resource]}" = "read" ] ; then
            echo "" 1>&2
            _log "Resource to be changed: $resource"
            echo "" 1>&2
            _log "Changes proposed:"
            printf "\n%s\n" "${changes[$resource]}" 1>&2
            echo "" 1>&2
            read -r -p "$0: Target this resource? [y/N] " answer
            if [ "$answer" = "y" ] ; then
                tochange[$resource]="1"
            fi
        fi
    done
}

_find_changes () {
    # If no log file was passed, run 'terraform plan' to generate an initial log file.
    if [ $# -lt 1 ] ; then
        _log "No log file passed; running a Terraform plan to collect changes..."
        echo "" 1>&2
        tmplogfile="$(mktemp -t tfta_log.XXXXXXXXXX)"

        "$TFTA_TERRAFORM_BIN" plan | tee "$tmplogfile"
        _identify_changes "$tmplogfile"

        rm -f "$tmplogfile"

    # Otherwise just look at the log files passed to us ("$@")
    else
        for f in "$@" ; do
            _identify_changes "$f"
        done
    fi
}

_prompt_changes () {
    # Loop over every identified change and ask the user about them
    if [ "${TFTA_USE_PROMPT:-}" = "dialog" ] && command -v dialog >/dev/null 2>/dev/null ; then
        _prompt_dialog
    else
        _prompt_text
    fi

    if [ ${#tochange[@]} -lt 1 ] ; then
        _log "No resources targeted; exiting..."
        if [ "$__opt_terraform_rm_plan" -eq 1 ] ; then
            rm -f "$TFTA_PLANFILE"
        fi
        return 0
    fi
}

_plan_changes () {
    for resource in "${!tochange[@]}" ; do
        tf_opts+=("-target=$resource")
    done

    if [ $__opt_dryrun -eq 1 ] ; then
        _log + "$TFTA_TERRAFORM_BIN" plan "${tf_opts[@]}" -out="$TFTA_PLANFILE"
    else
        set -x
        "$TFTA_TERRAFORM_BIN" plan "${tf_opts[@]}" -out="$TFTA_PLANFILE"
        set +x
    fi
}

_apply_changes () {
    if [ $__opt_dryrun -eq 1 ] ; then
        if [ $__opt_terraform_apply -eq 1 ] ; then
            _log + "$TFTA_TERRAFORM_BIN" apply "$TFTA_PLANFILE"
        fi
    else
        if [ $__opt_terraform_apply -eq 1 ] ; then
            echo "" 1>&2
            _log "Ready to apply changes."
            _log "Targeting the following resources: ${!tochange[*]}"
            echo "" 1>&2
            _log "Press enter to continue..."
            read -r answer
            set -x
            "$TFTA_TERRAFORM_BIN" apply "$TFTA_PLANFILE"
            set +x
            if [ "$__opt_terraform_rm_plan" -eq 1 ] ; then
                rm -f "$TFTA_PLANFILE"
            fi
        fi
    fi
}

_main () {
    declare -a tf_opts=()
    local tmplogfile

    _find_changes "$@"
    _prompt_changes

    if [ ${#tochange[@]} -gt 0 ] ; then
        _plan_changes
        _apply_changes
    fi
}

_usage () {
    cat <<EOUSAGE
Usage: $0 [OPTIONS] [LOGFILE [..]]

This script does the following:

 1. Takes a Terraform output log file, or barring that, runs 
    'terraform plan' and collects log output from that.
 2. Scans log output for changing resources.
 3. Prompts the user which resources they want to apply.
 4. Runs Terraform with -target option to apply those specific changes.

LOGFILE is the output of a 'terraform plan'. It can include colored
output or not. If you do not pass LOGFILE, runs 'terraform plan' in the
current directory to generate output to look through.

Pass environment variable TFTA_TERRAFORM_BIN to specify the command to
use for Terraform (default: 'terraform').

Options:
  -F FILE       Use FILE for Terraform plan \`-out=...\` option.
                (env var: TFTA_PLANFILE)
  -A            Once planning is done, apply the targeted changes.
  -R            If there are no targets to apply to, or once we run an apply successfully,
                remove the plan file (as it's no longer useful)
  -T            Terraformsh mode. Sets USE_PLANFILE=0 and TFTA_TERRAFORM_BIN=terraformsh
  -N            Dry-run mode.
  -h            This output
  -v            Verbose mode

EOUSAGE
    exit 1
}

__opt_terraformsh=0 __opt_terraform_apply=0 __opt_terraform_planfile=''
__opt_dryrun=0 __opt_verbose=0 __opt_terraform_rm_plan=0
while getopts "F:ARTNvh" args ; do
    case $args in
        F)  __opt_terraform_planfile="$OPTARG" ;;
        A)  __opt_terraform_apply=1 ;;
        R)  __opt_terraform_rm_plan=1 ;;
        T)  __opt_terraformsh=1 ;;
        N)  __opt_dryrun=1 ;;
        v)  __opt_verbose=1 ;;
        h)  _usage ;;
        *)  _errexit "Please pass correct _mktemp options" ;;
    esac
done
shift $((OPTIND-1))

# handle -T option
if [ $__opt_terraformsh -eq 1 ] ; then
    export USE_PLANFILE=0
    # Allow user to override from environment
    TFTA_TERRAFORM_BIN="${TFTA_TERRAFORM_BIN:-terraformsh}"
else
    TFTA_TERRAFORM_BIN="${TFTA_TERRAFORM_BIN:-terraform}"
fi

# handle -F option
if [ -n "${__opt_terraform_planfile:-}" ] ; then
    TFTA_PLANFILE="$__opt_terraform_planfile"
else
    TFTA_PLANFILE="${TFTA_PLANFILE:-$(mktemp -t tfta_plan)}"
fi


_main "$@"
