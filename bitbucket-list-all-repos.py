#!/usr/bin/env python3
import sys
import csv
import netrc # apparently just importing this makes 'requests' do the right thing!

import requests
from requests.auth import HTTPBasicAuth

team = sys.argv[1]

##Login
username = None
password = None

# apparently don't need this!! happens automatically! thanks, requests
#net = netrc.netrc()
#netauth = net.authenticators("api.bitbucket.org")

full_repo_list = []

# Request 10 repositories per page (and only their slugs), and the next page URL
#next_page_url = 'https://api.bitbucket.org/2.0/repositories/%s?pagelen=10&fields=next,values.links.clone.href,values.slug,name' % team
next_page_url = 'https://api.bitbucket.org/2.0/repositories/%s' % team

csvw = csv.writer(sys.stdout, quoting=csv.QUOTE_NONNUMERIC)
csvw.writerow( [ "slug","name","created_on","updated_on","has_issues","has_wiki" ] )

# Keep fetching pages while there's a page to fetch
while next_page_url is not None:
  if username != None and password != None:
    response = requests.get(next_page_url, auth=HTTPBasicAuth(username, password))
  else:
    response = requests.get(next_page_url)
    
  page_json = response.json()

  #print(response.text)
  #break

  # Parse repositories from the JSON
  for repo in page_json['values']:
    csvw.writerow( [ repo['slug'], repo['name'], repo['created_on'], repo['updated_on'], repo['has_issues'], repo['has_wiki'] ] )
    
  # Get the next page URL, if present
  # It will include same query parameters, so no need to append them again
  next_page_url = page_json.get('next', None)
