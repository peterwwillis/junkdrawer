#!/usr/bin/env bash
# gw - A Terminal User Interface wrapper to make Git worktrees easier to manage

# NOTE: We intentionally do NOT set -e here because dialog-driven control flow relies
# on inspecting exit codes (e.g. cancel vs OK). We add pipefail for safer pipes.
set -o pipefail
[ "${DEBUG:-0}" = "1" ] && set -x

declare -a worktree_list gw_commandlist
# worktree_list stores pairs: path branch path branch ... (Bash 3.x friendly)

DIALOG_OK=0
# Dialog exit/status codes reference (only DIALOG_OK currently used in logic):
#   DIALOG_ERROR=-1      Error from dialog
#   DIALOG_OK=0          User accepted (e.g. chose menu item / answered Yes)
#   DIALOG_CANCEL=1      User pressed Cancel
#   DIALOG_HELP=2        Help button (not wired here)
#   DIALOG_ITEM_HELP=2   (Alias) Item help code
#   DIALOG_EXTRA=3       Extra button (unused)
#   DIALOG_TIMEOUT=5     Timed out (unused)
#   DIALOG_ESC=255       ESC pressed (unused)

SCRIPT="$(basename "$0")"

gw_commandlist=(switch add convert remove list)

_die () { _err "$*" ; exit 1 ; }
_err () { printf "%s: Error: %s\n" "$SCRIPT" "$*" ; }
_debug () { printf "%s: Debug: %s\n" "$SCRIPT" "$*" 1>&2 ; }
_errifnot () { if [ "$1" -ne "$2" ] ; then _debug "Error: return status $1" ; return 1 ; fi ; return 0 ; }

_get_worktree_list () {
    # Populate global worktree_list with (path branch) pairs using git porcelain format.
    # We parse only 'worktree' and 'branch' lines; a blank line terminates an entry.
    worktree_list=()
    local wt='' branch='' line

    # Read git worktree list output line-by-line
    while IFS= read -r line; do
        # Blank line ends a record
        if [ -z "$line" ]; then
            if [ -n "$wt" ] && [ -n "$branch" ]; then
                worktree_list+=("$wt" "$branch")
            fi
            wt='' branch=''
            continue
        fi
        case "$line" in
            worktree\ *)
                # Everything after the first space is the path (may contain spaces)
                wt="${line#worktree }"
                ;;
            branch\ refs/heads/*)
                branch="${line#branch refs/heads/}"
                ;;
            branch\ *)
                branch="${line#branch }"
                ;;
            *)
                : # ignore other keys
                ;;
        esac
    done < <(git worktree list --porcelain)

    # Handle case where output does not end with newline
    if [ -n "$wt" ] && [ -n "$branch" ]; then
        worktree_list+=("$wt" "$branch")
    fi
}

# Get list of worktrees, prompt the user which one they want to enter,
# and then change to that directory
_gw_switch () {
    local repo_prefix current_branch
    repo_prefix="$(git rev-parse --show-prefix)"
    current_branch="$(git rev-parse --abbrev-ref HEAD)"

    _get_worktree_list
    if [ ${#worktree_list[@]} -eq 0 ]; then
        _debug "No worktrees found"
        return 1
    fi

    # Build dialog menu args
    local prompt
    prompt="$(printf "%s\n" \
        "Select a worktree branch to change current directory to." \
        "" \
        "Current branch is indicated with an asterisk.")"
    local menu=(dialog --title "Worktree switch" --menu "$prompt" 0 0 0 -1 "(DEFAULT)")
    local i=0 label target_dir target_branch commit_date
    for ((i=0; i<${#worktree_list[@]}; i+=2)); do
        target_dir="${worktree_list[i]}"; target_branch="${worktree_list[i+1]}"
        commit_date="$(git -C "$target_dir" log -1 --format=%cd --date=short 2>/dev/null || echo 'N/A')"
        if [ "$current_branch" = "$target_branch" ]; then
            label="* $target_branch"
        else
            label="  $target_branch"
        fi
        label="$label ($commit_date)"
        menu+=("$i" "$label")
    done

    # Show menu and get selection
    local tmpfile selection old_worktree_prefix
    tmpfile="$(mktemp)" || return 1
    "${menu[@]}" 2>"$tmpfile"
    _errifnot $? $DIALOG_OK || { rm -f "$tmpfile"; return 1; }
    selection="$(cat "$tmpfile")"; rm -f "$tmpfile"
    [ "$selection" = "-1" ] && return 0

    # Change to selected worktree directory
    target_dir="${worktree_list[selection]}"
    if [ ! -d "$target_dir" ]; then
        _debug "No such directory '$target_dir'"
        return 1
    fi
    echo "+ cd '$target_dir'"

    # If we have a prefix from previous worktree, try to cd into it if it exists.
    local prefixdir
    prefixdir="${old_worktree_prefix:-$repo_prefix}"
    if [ -n "$prefixdir" ] && [ -d "$target_dir/$prefixdir" ]; then
        unset old_worktree_prefix
        cd "$target_dir/$prefixdir" || _debug "Could not cd to '$target_dir/$prefixdir'"
    else
        if [ -n "$prefixdir" ] && [ ! -d "$target_dir/$prefixdir" ]; then
            _debug "Could not find '$prefixdir' in '$target_dir'; using repo root"
            old_worktree_prefix="$prefixdir"
        fi
        cd "$target_dir" || _debug "Could not cd to '$target_dir'"
    fi
}

# Add a new worktree, optionally creating a new branch
_gw_add () {
    local gitroot current_branch
    gitroot="$(git rev-parse --show-toplevel)" || return 1
    current_branch="$(git rev-parse --abbrev-ref HEAD)" || return 1

    # Dialog form collects three fields (newline separated in tmp file):
    #   0 -> create flag (y/n)
    #   1 -> origin branch (base branch or existing branch)
    #   2 -> new branch name (iff create flag = y)
    local formdesc
    formdesc="$(printf "%s\n" \
        "Specify the following to add a new git worktree:" \
        "  1) 'Create new branch?' - put 'y' to create a new branch, and fill out the 'New branch' section." \
        "  2) 'Origin branch' - If not creating a new branch, this is the branch to use. If creating a new branch, this is the origin branch used to start a new branch." \
        "  3) 'New branch' - The new branch name, if created.")"

    local execlist=(
        dialog --title "Add a new worktree" --form "$formdesc" 0 0 0 \
            "Create new branch (y/n)" 1 1 "y" 1 25 30 0 \
            "Origin branch" 2 1 "$current_branch" 2 25 99 0 \
            "New branch" 3 1 "" 3 25 99 0
    )

    # Execute dialog and capture results
    local tmpfile create_flag origin_branch new_branch path
    local -a result=() args=()
    tmpfile="$(mktemp)" || return 1
    "${execlist[@]}" 2>"$tmpfile"
    _errifnot $? $DIALOG_OK || { rm -f "$tmpfile"; return 1; }

    # Read newline-separated fields into result array.
    # Previous code used: IFS=$'\n' read -r -a result <"$tmpfile"
    # That only reads ONE line (the first) into the array, leaving origin/new branch empty.
    # We need to read all lines; avoid readarray for wider Bash compatibility.
    while IFS= read -r line; do
        # Skip possible trailing empty line
        [ -z "$line" ] && continue
        result+=("$line")
    done <"$tmpfile"
    rm -f "$tmpfile"

    # Parse results
    create_flag="${result[0]:-}"    # y / n
    origin_branch="${result[1]:-}"   # existing branch or base
    new_branch="${result[2]:-}"      # new branch name (if create)
    if [ -z "$origin_branch" ]; then
        _debug "No origin branch name (dialog form parse error?)"; return 1
    fi

    # Build the git worktree add command
    args=(git worktree add)
    local parent_dir
    parent_dir="$(dirname "$gitroot")"
    case "$create_flag" in
        y|Y)
            if [ -z "$new_branch" ]; then
                _debug "No new branch name"; return 1
            fi
            path="$parent_dir/$new_branch"
            args+=("-b" "$new_branch" "$path" "$origin_branch")
            ;;
        *)
            path="$parent_dir/$origin_branch"
            args+=("$path" "$origin_branch")
            ;;
    esac
    echo "+ ${args[*]}"

    # Execute the git worktree add command
    if "${args[@]}" ; then
        echo "+ cd '$path'"
        cd "$path" || return 1
    fi
}

# Convert a single-branch repo into a worktree-compatible layout.
# Moves all files into a new subdirectory named for the current branch.
# After conversion, the original root contains only branch directories + .gwrc.
# Requires user confirmation; aborts if destination exists or parent already has .gwrc.
_gw_convert () {
    local execlist=() gitroot branchname newdir prompttxt dest dest_parent top_component
    gitroot="$(git rev-parse --show-toplevel)" || return 1
    branchname="$(git rev-parse --abbrev-ref HEAD)" || return 1
    dest="$gitroot/$branchname"
    dest_parent="$(dirname "$dest")"
    top_component="${branchname%%/*}"

    # Preconditions
    if [ -e "$(dirname "$gitroot")/.gwrc" ] ; then
        _debug "Parent is already a gw directory; conversion likely unnecessary"
        return 1
    fi
    if [ -e "$dest" ] ; then
        _debug "Destination '$dest' already exists; aborting convert"
        return 1
    fi

    # Confirm with user
    prompttxt="$( printf "%s\n" \
        "Repository: $gitroot" \
        "Remote:" "$(git remote -v)" \
        "" \
        "Will create branch directory: $dest" \
        "'convert' copies ALL files (tracked, untracked, ignored) including .git into a new directory," \
        "then removes originals from the parent, leaving only branch directories + .gwrc." \
        "" \
        "Continue?" )"
    execlist=(dialog --title "Convert this repository to a worktree subdirectory" --yesno "$prompttxt" 0 0)
    "${execlist[@]}"
    _errifnot $? $DIALOG_OK || return 1

    # Create temporary directory for copying files
    newdir="$(mktemp -d)" || { _debug "Failed to allocate temp dir"; return 1; }

    # Copy phase: include hidden and regular entries (except . and ..). Use dotglob/nullglob safely.
    (
        shopt -s dotglob nullglob
        local items=(*)
        if [ ${#items[@]} -eq 0 ] ; then
            _debug "Nothing to copy? (Empty directory)"; exit 1
        fi
        cp -a "${items[@]}" "$newdir/" || exit 1
    ) || { _debug "Copy phase failed"; return 1; }

    # Create destination parent path (supports branch names with slashes)
    mkdir -p "$dest_parent" || { _debug "Failed to create parent '$dest_parent'"; return 1; }

    # Move the copied snapshot into its final branch directory
    if ! mv "$newdir" "$dest" ; then
        _debug "Move of '$newdir' to '$dest' failed"
        return 1
    fi

    # Write/overwrite .gwrc at parent to mark origin workdir
    echo "ORIGIN_WORKDIR=\"$dest\"" > .gwrc || _debug "Failed writing .gwrc"

    # Remove original items from root EXCEPT the branch top component (and .gwrc we just wrote)
    (
        shopt -s dotglob nullglob
        for f in *; do
            [ "$f" = "$top_component" ] && continue
            [ "$f" = ".gwrc" ] && continue
            rm -rf -- "$f"
        done
    )
    cd "$branchname" || _debug "Converted but failed to cd into branch dir '$branchname'"
}

# Remove the currently checked-out worktree (by branch) after switching to a fallback.
_gw_remove () {
    # Strategy:
    #   1. Collect current worktree path and first alternate path.
    #   2. Confirm user intent.
    #   3. cd into alternate path (so removal isn't performed inside target).
    #   4. Run `git worktree remove` on the current worktree path.

    local execlist=() gitroot branchname prompttxt cur_path alt_path
    gitroot="$(git rev-parse --show-toplevel)" || return 1
    branchname="$(git rev-parse --abbrev-ref HEAD)" || return 1
    _get_worktree_list
    if [ ${#worktree_list[@]} -lt 2 ]; then
        _debug "No worktree entries found"; return 1
    fi

    # Scan pair list: path branch
    local i path branch
    for ((i=0; i<${#worktree_list[@]}; i+=2)); do
        path="${worktree_list[i]}"; branch="${worktree_list[i+1]}"
        if [ "$branch" = "$branchname" ]; then
            cur_path="$path"
        elif [ -z "${alt_path:-}" ]; then
            alt_path="$path"
        fi
    done
    if [ -z "${cur_path:-}" ]; then _debug "Could not find current worktree path"; return 1; fi
    if [ -z "${alt_path:-}" ]; then _debug "Refusing to remove the only remaining worktree"; return 1; fi

    # Confirm with user
    prompttxt="$( printf "%s\n" \
        "Repository: $gitroot" \
        "Remote:" "$(git remote -v)" \
        "" \
        "Current worktree path: $cur_path" \
        "Switching to:        $alt_path" \
        "" \
        "Remove worktree for branch '$branchname'?" )"
    execlist=(dialog --title "Remove worktree" --yesno "$prompttxt" 0 0)
    "${execlist[@]}"

    # Check the result
    _errifnot $? $DIALOG_OK || return 1

    # Switch to alternate worktree
    cd "$alt_path" || { _debug "Failed to cd to '$alt_path'"; return 1; }

    # Finally, remove the current worktree
    git worktree remove "$cur_path"
}

# Show a simple dialog listing current worktrees; handle empty edge case.
_gw_list () {
    local list
    if ! list="$(git worktree list -v 2>/dev/null)" ; then
        dialog --title "Worktree list" --msgbox "(Error running 'git worktree list')" 0 0
        return 1
    fi
    if [ -z "$list" ]; then
        dialog --title "Worktree list" --msgbox "No worktrees found." 0 0
        return 0
    fi
    dialog --title "Worktree list" --msgbox "$list" -1 -1
}

# Main interactive menu for selecting a subcommand.
# Builds a numeric menu of entries in gw_commandlist, runs chosen command.
_gw () {
    local prompt gitroot
    gitroot="$(git rev-parse --show-toplevel)" || return 1
    prompt="$(printf "%s\n" "Repository: $gitroot" "" "Select a wrapper command")"
    
    # Build menu args
    local menu=() idx=0
    menu=(dialog --title "Git Worktree wrapper" --menu "$prompt" 0 0 0 -1 "(NONE)")
    for cmd in "${gw_commandlist[@]}"; do
        menu+=("$idx" "$cmd")
        idx=$((idx+1))
    done

    # Show menu and get selection
    local tmpfile
    tmpfile="$(mktemp)" || return 1
    "${menu[@]}" 2>"$tmpfile"
    _errifnot $? $DIALOG_OK || { rm -f "$tmpfile"; return 1; }
    local selection
    selection="$(cat "$tmpfile")"
    rm -f "$tmpfile"
    [ "$selection" = "-1" ] && return 0

    # Run the selected command
    _gw_runcmd "${gw_commandlist[$selection]}"
}

# Run a specific command (non-interactive mode)
_gw_runcmd () {
    case "$1" in
        -h|--help)  _gw_usage ;;
        sw|switch)  _gw_switch ;;
        a|add)      _gw_add ;;
        convert)    _gw_convert ;;
        remove)     _gw_remove ;;
        list)       _gw_list ;;
        *)          _debug "Invalid command: '$1'" ;;
    esac
}

# Check for required dependencies
_check_deps () {
    for cmd in git dialog ; do
        command -v "$cmd" >/dev/null || _die "Could not find command: $cmd"
    done
}

_gw_usage () {
    cat <<EOUSAGE
gw: Bash wrapper around 'git worktree'

(Source this script into your shell with: \`source $SCRIPT\` ;
 then use the \`gw\` command)

Usage: gw [COMMAND]

1. Keep a directory 'foo', and in that directory clone a Git repository, with the
   name of your main branch (so, 'foo/main').

2. Change to that directory and run 'gw' (if 'gw' is in your path, this will find
   'gw' and load it into your shell, which will enable it to change the current
   directory of your shell).

3. You can then select a command to run and the wrapper will make it easier to use.

Commands:

    switch          Switch to a worktree directory. Looks up your worktree list,
                    presents you with a list of branches, and when you select one,
                    your current shell will change to the directory of that worktree.

    add             Add a new worktree directory. Put in the name of the source branch
                    and the name of a new branch, and a new worktree will be created
                    with the new branch name (ex. 'foo/new-branch').

    convert         Convert a git repository into a worktree-compatible form. Basically
                    it just makes a new temp directory, copies all the files in the current
                    directory there, removes all the files in the current directory, and
                    then moves the temp directory into the current one with the name of the
                    branch that was previously checked out. From here you can run workdir
                    commands and they will create directories in a parent directory
                    (using the name of the branch you want a worktree for).

    list            List the current worktrees.
EOUSAGE
    return 1
}


# Run the 'gw' command after sourcing into your shell
gw () {

    _check_deps

    # If .gwrc exists in current directory, source it to get ORIGIN_WORKDIR and cd there.
    if [ -r .gwrc ] ; then
        # shellcheck disable=SC2016  # We intentionally use single quotes to prevent expansion in this shell; subshell handles it.
        origin_workdir="$(env -i sh -c 'set -a; . ./.gwrc ; echo $ORIGIN_WORKDIR')"
        _debug "Found .gwrc; moving to origin worktree '$origin_workdir'"
        cd "$origin_workdir" || _debug "Failed to cd to origin worktree '$origin_workdir'"
    fi

    if ! git rev-parse 2>/dev/null ; then
        _debug "Current directory is not a Git work tree"
        return 1
    fi

    # If no args, run interactive menu; else run specified command.
    if [ $# -lt 1 ] ; then
        _gw
    else
        _gw_runcmd "$@"
    fi

}
