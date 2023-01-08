#!/usr/bin/env sh
set -eu
[ "${DEBUG:-0}" = "1" ] && set -x

gcloud iam service-accounts list --format json | jq -r ".[].email" | xargs -n1 -I{} sh -c 'a="{}"; keys="$(gcloud iam service-accounts keys list --iam-account "$a" --format "value(name)" | xargs )" ; printf "iam_account=\"%s\" keys=\"%s\"\n" "$a" "$keys"'
