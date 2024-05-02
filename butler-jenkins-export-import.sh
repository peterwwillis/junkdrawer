#!/usr/bin/env bash
# butler-jenkins-export-import.sh - Use Butlet to export and import jobs and credentials for Jenkins servers

set -e -o pipefail -u

if [ ! -e butler ] ; then
    wget https://s3.us-east-1.amazonaws.com/butlercli/1.0.0/linux/butler
    chmod 755 butler
fi
export PATH="$PATH:`pwd`"

_butler_export () {
    # Get the plugins list
    butler plugins export --server "$JENKINS_URL" -u "$JENKINS_USR" -p "$JENKINS_PSW" \
        | cut -d '|' -f 2,3 | tr -d ' ' | grep '^[a-zA-Z]' | sort | sed -e 's/|/:/' > plugins.txt

    # Get the jobs and credentials
    butler jobs export --server "$JENKINS_URL" -u "$JENKINS_USR" -p "$JENKINS_PSW"
    butler credentials decrypt --server "$JENKINS_URL" -u "$JENKINS_USR" -p "$JENKINS_PSW" -f "." > decryptedCredentials.json

    (
        cd jobs
        for d in * ; do
            (
                cd "$d"
                butler jobs export --server "$JENKINS_URL" -u "$JENKINS_USR" -p "$JENKINS_PSW" -f "$d"
                butler credentials decrypt --server "$JENKINS_URL" -u "$JENKINS_USR" -p "$JENKINS_PSW" -f "$d" > decryptedCredentials.json
            )
        done
    )
}

_butler_import () {
    # Get the plugins list
    butler plugins import --server "$JENKINS_URL" -u "$JENKINS_USR" -p "$JENKINS_PSW"  < plugins.txt

    # Get the jobs and credentials
    butler jobs import --server "$JENKINS_URL" -u "$JENKINS_USR" -p "$JENKINS_PSW"
    butler credentials apply --server "$JENKINS_URL" -u "$JENKINS_USR" -p "$JENKINS_PSW" -f "." < decryptedCredentials.json

    (
        cd jobs
        for d in * ; do
            (
                cd "$d"
                butler jobs import --server "$JENKINS_URL" -u "$JENKINS_USR" -p "$JENKINS_PSW" -f "$d"
                butler credentials apply --server "$JENKINS_URL" -u "$JENKINS_USR" -p "$JENKINS_PSW" -f "$d" < decryptedCredentials.json
            )
        done
    )
}

if [ $# -lt 1 ] ; then
    echo "Usage: $0 CMD"
    echo ""
    echo "Commands:"
    echo "   export"
    echo "   import"
    exit 1
elif [ "$1" = "export" ] ; then
    _butler_export
elif [ "$1" = "import" ] ; then
    _butler_import
fi
