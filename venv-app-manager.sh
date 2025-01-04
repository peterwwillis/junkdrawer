#!/usr/bin/env bash
# venv-app-manager.sh - Manages a set of Python venv applications for you
#
# Sometimes you may want to install a bunch of Python applications, but your
# system wants you to use a venv (virtual environment) to install Python
# packages. This script helps you:
#
#  - Create a venv for each app you want to install
#  - Run pip for you
#  - Run extra commands you can configure per-application
#  - Add each venv bin/ directory to the end of your PATH so you can execute
#    the installed apps easily
#
# So this is basically a very crappy, small application manager for Python.
# (sigh.... not another one............ !!!)

set -eu
[ "${DEBUG:-0}" = "1" ] && set -x

#################
### Global vars

# In case HOME was not set
HOME="${HOME:-$(getent passwd $(id -un) | cut -d : -f 6)}"

SCRIPTDIR="$(dirname "${BASH_SOURCE[0]}")"
SCRIPTNAME="$(basename "${BASH_SOURCE[0]}")"

export VENV_BASEDIR="${VENV_BASEDIR:-$HOME/venv}"
export VENV_CONFDIR="${VENV_CONFDIR:-$HOME/.config/venv-app-manager}"

VENV_OPT_FORCE=0

###############
#### Functions

_info () { printf "%s: Info: %s\n" "$SCRIPTNAME" "$*" ; }
_err () { printf "%s: Error: %s\n" "$SCRIPTNAME" "$*" 1>&2 ; }
_errexit () { _err "$*" ; exit 1 ; }
_tempfile () {
    oldmask="$(umask)"
    umask 0077
    mktemp
    umask "$oldmask"
}
_runscript () {
    local script="$1"
    local tmpf="$(_tempfile)"
    printf "%s\n" "$script" > "$tmpf"
    if ! bash "$tmpf" ; then
        _err "Bash could not run SCRIPT '$tmpf':"
        _err "$(cat "$tmpf")"
    fi
    rm -f "$tmpf"
}

_venv_confload () {
    arg="${1:-}"
    if [ -d "$VENV_CONFDIR" ] ; then
        if [ -n "$arg" ] ; then

            if [ -d "$VENV_CONFDIR/venv/$arg" ] ; then
                export VENV_SETUPDIR="$VENV_CONFDIR/venv/$arg"

                if [ -e "$VENV_SETUPDIR/config.sh" ] ; then
                    _info "Found venv '$arg' setup config file '$VENV_SETUPDIR/config.sh'; loading..."
                    . "$VENV_SETUPDIR/config.sh"
                fi
            fi

        else
            if [ -e "$VENV_CONFDIR/config.sh" ] ; then
                _info "Found config file '$VENV_CONFDIR/config.sh'; loading..."
                . "$VENV_CONFDIR/config.sh"
            fi
        fi
    fi
}
_venv_clearvar () {
    unset VENV_SETUPDIR # The directory with venv-specific setup instructions
    unset PREINSTALL POSTINSTALL PREINSTALL_SCRIPT POSTINSTALL_SCRIPT
    unset PYTHON_REQUIRES
}
_venv_prep () {
    mkdir -p "$VENV_BASEDIR"

    if [ -z "${VENV_CONFDIR:-}" ] ; then
        for dir in "$HOME"/.config/venv-app-manager "$HOME"/.venv-app-manager ; do
            if [ -d "$dir" ] ; then
                export VENV_CONFDIR="$dir"
                break
            fi
        done
    fi

    mkdir -p "$VENV_CONFDIR"
}
_venv_install () {
    local _auto_install=0
    while getopts "af" arg ; do
        case "$arg" in
            a)          _auto_install=1 ;;
            f)          VENV_OPT_FORCE=1 ;;
        esac
    done
    shift $((OPTIND-1))

    [ $# -gt 0 ] || _errexit "You must pass arguments to this command"
    local venv_name="$1"
    export VENV_DIR="$VENV_BASEDIR/$venv_name"

    if [ -d "$VENV_DIR" ] && [ ! "${VENV_OPT_FORCE:-0}" = "1" ] ; then
        _errexit "Virtualenv directory '$VENV_DIR' already exists"
    fi

    _venv_clearvar
    _venv_confload "$venv_name"

    if declare -p PREINSTALL 2>/dev/null 1>&2 && [ ${#PREINSTALL[@]} -gt 0 ] ; then
        bash -c "${PREINSTALL[@]}"
    fi
    if declare -p PREINSTALL_SCRIPT 2>/dev/null 1>&2 ; then
        _runscript "$PREINSTALL_SCRIPT" || _errexit "Could not run PREINSTALL_SCRIPT! Exiting"
    fi
    if [ -n "${VENV_SETUPDIR:-}" ] && [ -e "$VENV_SETUPDIR/preinstall.sh" ] ; then
        bash "$VENV_SETUPDIR/preinstall.sh" || _errexit "Could not run preinstall.sh! Exiting"
    fi

    # Installing the venv!
    python3 -m venv "$VENV_DIR"

    if [ "$_auto_install" = "1" ] ; then
        "$VENV_DIR/bin/pip" install "$venv_name"
    fi

    if declare -p PYTHON_REQUIRES 2>/dev/null 1>&2 ; then
        "$VENV_DIR/bin/pip" install "${PYTHON_REQUIRES[@]}"

    elif [ -n "${VENV_SETUPDIR:-}" ] && [ -e "$VENV_SETUPDIR/requirements.txt" ] ; then
        "$VENV_DIR/bin/pip" install -r "$VENV_SETUPDIR/requirements.txt"
    fi

    if declare -p POSTINSTALL 2>/dev/null 1>&2 && [ ${#POSTINSTALL[@]} -gt 0 ] ; then
        bash -c "${POSTINSTALL[@]}" || _errexit "Could not run POSTINSTALL! Exiting"
    fi
    if declare -p POSTINSTALL_SCRIPT 2>/dev/null 1>&2 ; then
        _runscript "$POSTINSTALL_SCRIPT" || _errexit "Could not run POSTINSTALL_SCRIPT! Exiting"
    fi
    if [ -n "${VENV_SETUPDIR:-}" ] && [ -e "$VENV_SETUPDIR/postinstall.sh" ] ; then
        bash "$VENV_SETUPDIR/postinstall.sh" || _errexit "Could not run postinstall.sh! Exiting"
    fi
}
_venv_upgrade () {
    local _auto_install=0
    while getopts "a" arg ; do
        case "$arg" in
            a)          _auto_install=1 ;;
        esac
    done
    shift $((OPTIND-1))

    [ $# -gt 0 ] || _errexit "You must pass arguments to this command"
    local venv_name="$1"
    export VENV_DIR="$VENV_BASEDIR/$venv_name"

    _venv_clearvar
    _venv_confload "$venv_name"

    if [ "$_auto_install" = "1" ] ; then
        "$VENV_DIR/bin/pip" install --upgrade "$venv_name"
    fi

    if declare -p PYTHON_REQUIRES 2>/dev/null 1>&2 ; then
        "$VENV_DIR/bin/pip" install --upgrade "${PYTHON_REQUIRES[@]}"

    elif [ -n "${VENV_SETUPDIR:-}" ] && [ -e "$VENV_SETUPDIR/requirements.txt" ] ; then
        "$VENV_DIR/bin/pip" install --upgrade -r "$VENV_SETUPDIR/requirements.txt"
    fi
}
_venv_remove () {
    [ $# -gt 0 ] || _errexit "You must pass arguments to this command"
    local venv_name="$1"
    export VENV_DIR="$VENV_BASEDIR/$venv_name"

    _venv_clearvar
    _venv_confload "$venv_name"

    read -r -p "Are you sure you want to remove venv '$VENV_DIR'? [y/N] " ANSWER
    if [ "$ANSWER" = "y" -o "$ANSWER" = "Y" ] ; then
        _info "Removing venv '$venv_name' ..."
        rm -rf "$VENV_DIR"
    fi
}
_venv_list () {
    for dir in "$VENV_BASEDIR"/* ; do
        bn="$(basename "$dir")"
        [ ! "$bn" = "*" ] || break
        echo "$bn"
    done
}
_venv_shellenv () {
    local -a tmppaths=()
    for dir in "$VENV_BASEDIR"/* ; do
        bn="$(basename "$dir")"
        [ ! "$bn" = "*" ] || break
        if [ -d "$dir/bin" ] ; then
            tmppaths+=("$dir/bin")
        fi
    done
    if [ ${#tmppaths[@]} -gt 0 ] ; then
        for path in "${tmppaths[@]}" ; do
            export PATH="$PATH:$path"
        done
        printf "export PATH=\"%s\"\n" "$PATH"
    fi
}

_usage () {
    cat <<EOUSAGE
Usage: $SCRIPTNAME COMMAND [ARG ..]

Manages Python virtual environments for you.

Commands:

    install [OPTS] NAME     Installs a venv NAME.

        Options:    -a      Auto-install package NAME in venv NAME
                    -f      Force install even if NAME exists

    upgrade NAME            Upgrade the packages in venv NAME. Doesn't do
                            anything by default unless you have configuration
                            that specifies packages.

        Options:    -a      Auto-upgrade package NAME in venv NAME

    remove NAME             Removes a venv NAME

    list                    Lists all installed venvs

    shellenv                Prints your PATH plus the paths to the venv bin
                            directories so you can find all the executables


Config files specific to a venv 'NAME' can be saved in a directory
called '$VENV_CONFDIR/venv/NAME'.

In that directory you can keep the following files:

    - config.sh              A text file with the following variables:
                                PREINSTALL
                                    A Bash array of commands to run before install
                                PREINSTALL_SCRIPT
                                    A Bash variable to include a Bash script to run
                                    before install
                                POSTINSTALL
                                    A Bash array of commands to run after install
                                POSTINSTALL_SCRIPT
                                    A Bash variable to include a Bash script to run
                                    after install
                                PYTHON_REQUIRES
                                    A Bash array of Python packages to install
                                    with pip
    - requirements.txt      A text file with Python packages to install with pip
    - preinstall.sh         A Bash script to run before install
    - postinstall.sh        A Bash script to run after install

EOUSAGE
    exit 1
}


#################################
### Main command execution time!

_venv_prep


if [ $# -gt 0 ] ; then
    cmd="$1"; shift
    case "$cmd" in
        install)        _venv_install "$@" ;;
        upgrade)        _venv_upgrade "$@" ;;
        remove)         _venv_remove "$@" ;;
        list)           _venv_list "$@" ;;
        shellenv)       _venv_shellenv "$@" ;;
        *)              _errexit "Invalid command '$cmd'" ;;
    esac
else
    _usage
fi
