#!/usr/bin/env sh
curl -nsSfL "https://api.bitbucket.org/2.0/repositories/$BITBUCKET_TEAM?pagelen=10&fields=next,values.links.clone.href,values.slug" | jq .
