#!/usr/bin/env bash
set -e -o pipefail
curl -sLo - https://api.wordpress.org/secret-key/1.1/salt/ | sed -e "s/^define('//g; s/',[[:space:]]\+/=/g; s/');/'/g"
