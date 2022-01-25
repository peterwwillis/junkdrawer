#!/usr/bin/env bash
set -e
[ x"$DEBUG" = "x1" ] && set -x

CONF="$HOME/.adldaptoolrc"
_load_conf () { if [ -r "$CONF" ] ; then . "$CONF" ; fi ; }
_load_conf

[ -n "$AD_PORT" ]       || AD_PORT="3269"
[ -n "$AD_SERVER" ]     || read -r -p "Enter your active directory server host: " AD_SERVER
[ -n "$SEARCH_BASE" ]   || read -r -p "Enter your search base (ex. DC=mydomain,DC=com): " SEARCH_BASE
[ -n "$BIND_DN" ]       || read -r -p "Enter your AD user's full Bind DN: " BIND_DN

# Sample Bind DN:
#   BIND_DN="CN=Lastname\, Firstname,OU=Country - City,OU=Standard,OU=BusinessUnit,OU=Users,OU=User Accounts,DC=my,DC=domain,DC=com"
#

### Internal functions
_save_conf () {
    cat > "$CONF" <<EOCONF
AD_SERVER="$AD_SERVER"
AD_PORT="$AD_PORT"
SEARCH_BASE="$SEARCH_BASE"
BIND_DN="$BIND_DN"
LDAP_PASSWDRC="$LDAP_PASSWDRC"
EOCONF
}
_save_conf
_err () { env printf "$1\n" ; exit 1 ; }
_adsearch () {
    local SEARCH_PATH="$1"; shift
    local ldappwopt
    # In order to set an LDAP_PASSWDRC file, it must have NO NEWLINE OR LINEFEED CHARACTERS!
    # Example:
    #    read -r PASSWD ; printf "%s" "$PASSWD" > ~/.ldap-credential
    # Note that if you don't use single quotes, the shell will interperet some
    # characters in your password as shell commands.
    [ -n "$LDAP_PASSWDRC" ] && ldappwopt="-y $LDAP_PASSWDRC"
    set -x
    # Note: if you don't use "ldaps://" below, add "-ZZ" to enforce TLS certificate use
    ldapsearch $ldappwopt -o ldif-wrap=no -LLL -H "ldaps://$AD_SERVER:$AD_PORT" -b "$SEARCH_BASE" -D "$BIND_DN" -W "$SEARCH_PATH" "$@"
    # to get more than 1500 results from Active Directory, append  'member;range=1500-2999' or similar as an extra argument
    [ x"$DEBUG" = "x1" ] || set +x
}

### Functions called by command-line options
_adsearch_query () {
    [ $# -gt 0 ] || _err "Usage: $0 query QUERYSTRING [ATTRIBUTE ..]
    Run an arbitrary LDAP search query and attributes."
    local QUERY="($1)"; shift
    _adsearch "$QUERY" "$@"
}
_adsearch_user () {
    [ $# -gt 0 ] || _err "Usage: $0 user USERNAME [ATTRIBUTE ..]
    This uses the sAMAccountName= search field to find an AD username."
    local user="$1"; shift
    _adsearch "(sAMAccountName=$user)" "$@"
}
_adsearch_group () {
    [ $# -gt 0 ] || _err "Usage: $0 group GROUPNAME [..]
    Note: the GROUPNAME already includes the CN= prefix."
    local string="(CN=$1)"; shift
    _adsearch "$string" "$@"
}
_adsearch_members () {
    [ $# -gt 0 ] || _err "Usage: $0 members GROUPNAME
    This looks up 'member' attributes of a group and extracts the first part of the common names."
    local group="$1"; shift
    _adsearch_group "$group" member | grep "member:" | cut -d : -f 2- | sed -e 's/\([^\\],\).*/\1/' | cut -d = -f 2- | sed -e 's/\\//;s/,$//' | sort
}
_adsearch_name () {
    [ $# -gt 0 ] || _err "Usage: $0 name NAME [ATTRIBUTE ..]
    This looks up a record by the person's name. Example:
        $0 name 'Willis*'"
    local name="$1"; shift
    name="$(printf "%s" "$name" | sed -e 's/\([()]\)/\\\1/g')" 
    _adsearch "(name=$name)" "$@"
}

### Generic functions
_cmds () {
    grep "^_adsearch_" "$0" | sed -e 's/^_adsearch_\([0-9a-zA-Z_]\+\)[[:space:]]\+.*/\1/'
}
_usage () {
    cmds=$(_cmds | sed -e 's/^/   /')
    _err "Usage: $0 COMMAND [ARGS ..]

Commands:
$cmds"
}

### Start general script execution

[ $# -gt 0 ] || _usage

CMD="$1"; shift
if ! _cmds | grep -q "^$CMD$" ; then
    _usage
fi

"_adsearch_$CMD" "$@"
