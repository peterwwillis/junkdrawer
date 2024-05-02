#!/usr/bin/env python3
# github-list-users.py - List GitHub users using 'github' Python library

""" Lists all valid GitHub users that we should allow in a groups.yml file.

    To run this script, you must have the PyGithub Python package installed,
    and have a GITHUB_TOKEN environment variable. The token must have access
    to the org data, and you may need admin privileges on the org to look
    up the outside collaborators.
 """

import os, sys
import github

users = set()

g = github.Github( os.environ['GITHUB_TOKEN'] )
o = g.get_organization( os.environ['GITHUB_ORG'] )
m = o.get_members()
for u in m:
    users.add( u.login )
oc = o.get_outside_collaborators()
for u in oc:
    users.add( u.login )

print("\n".join(users))
