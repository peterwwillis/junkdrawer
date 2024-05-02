#!/usr/bin/env sh
# bitbucket-list-all-repos.sh - Return a JSON document of available Bitbucket repositories for a specific \$BITBUCKET_TEAM

curl -nsSfL "https://api.bitbucket.org/2.0/repositories/$BITBUCKET_TEAM?pagelen=10&fields=next,values.links.clone.href,values.slug" | jq .
