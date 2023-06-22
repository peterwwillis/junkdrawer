#!/usr/bin/env sh
set -eu
[ "${DEBUG:-0}" = "1" ] && set -x

curl \
    -H "Metadata-Flavor: Google" \
    "http://metadata.google.internal/computeMetadata/v1/instance/?recursive=true"
ret=$?
echo ""
exit $ret
