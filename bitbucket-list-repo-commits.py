#!/usr/bin/env python3
# bitbucket-list-repo-commits.py - Return a CSV of Bitbucket repositories

import sys, requests
from requests.auth import HTTPBasicAuth


team = sys.argv[1]
repo = sys.argv[2]

##Login
username = None
password = None

full_repo_list = []

# Request 100 repositories per page (and only their slugs), and the next page URL
#next_page_url = 'https://api.bitbucket.org/2.0/repositories/%s?pagelen=10&fields=next,values.links.clone.href,values.slug' % team
next_page_url = 'https://api.bitbucket.org/2.0/repositories/%s/%s/commits' % (team, repo)

# Keep fetching pages while there's a page to fetch
while next_page_url is not None:
  if username != None and password != None:
    response = requests.get(next_page_url, auth=HTTPBasicAuth(username, password))
  else:
    response = requests.get(next_page_url)
    
  page_json = response.json()

  print(response.text)
  break

  # Parse repositories from the JSON
  for repo in page_json['values']:
    reponame=repo['slug']
    repohttp=repo['links']['clone'][0]['href']
    repogit=repo['links']['clone'][1]['href']

    print( reponame + "," + repohttp + "," + repogit )
    full_repo_list.append(repo['slug'])
    

  # Get the next page URL, if present
  # It will include same query parameters, so no need to append them again
  next_page_url = page_json.get('next', None)
