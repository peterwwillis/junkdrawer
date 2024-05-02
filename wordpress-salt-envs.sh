#!/usr/bin/env bash
# wordpress-salt-envs.sh - Download the default salts for WordPress

set -e -o pipefail
curl -sLo - https://api.wordpress.org/secret-key/1.1/salt/ | sed -e "s/^define('//g; s/',[[:space:]]\+/=/g; s/');/'/g"
