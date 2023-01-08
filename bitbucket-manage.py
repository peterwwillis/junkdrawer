#!/usr/bin/env python3
# bitbucket-manage.py
# Copyright (C) 2023 Peter W <31324861+peterwwillis@users.noreply.github.com>

import io
import os
import sys
import csv
import netrc
import requests
from datetime import datetime
import dateutil
from dateutil import parser, tz
import getopt

os.environ['PYTHONUNBUFFERED'] = '1'
sys.stdout = io.TextIOWrapper(open(sys.stdout.fileno(), 'wb', 0), write_through=True)

class ManageBitbucket:
    csvw = None
    stdin_buffer = None

    def post_api_json(self, url, payload):
        my_headers['Content-Type'] = 'application/json'
        try:
            response = requests.post(url, headers=my_headers, data=payload)
            js = response.json()
        except Exception as e:
            if response.status_code > 199 and response.status_code < 300: pass
            print("Error POSTing page '%s': '%s'" % (url, response), file=sys.stderr)
            return(None)
        return js

    def delete_api_json(self, url):
        try:
            response = requests.api.delete(url)
            js = response.json()
        except Exception as e:
            if response.status_code > 199 and response.status_code < 300: pass
            print("Error DELETEing page '%s': '%s'" % (url, response), file=sys.stderr)
            return(None)
        return js

    def get_api_json(self, url):
        next_page_token = None
        next_page_url = url[:]
        while next_page_url is not None:
            try:
                response = requests.get(next_page_url)
                page_json = response.json()
            except Exception as e:
                if response.status_code > 199 and response.status_code < 300: pass
                print("Error getting page '%s': '%s'" % (next_page_url, e), file=sys.stderr)
                return(None)

            yield page_json

            next_page_token = page_json.get('next', None)
            if next_page_token != None:
                next_page_url = next_page_token
            else:
                next_page_url = None

    def load_list(self,arg):
        # arg can be a literal string, or a "file:///path/to/a/file", or "-" to read from stdin.
        # returns a list.
        args=[arg]
        if arg.startswith("file://"):
            with open(arg[7:]) as f:
                argss = f.read().splitlines()
        elif arg == "-":
            if self.stdin_buffer == None:
                self.stdin_buffer = sys.stdin.read().splitlines()
            args = self.stdin_buffer
        return(args)

    def _repos(self, args):
        org = args[0]
        url = "https://api.bitbucket.org/2.0/repositories/%s" % org
        for j in self.get_api_json(url):
            if j is None: continue
            if not 'values' in j: continue
            for key in j['values']:
                yield key

    def _repo_deploy_keys(self, args):
        org, repos = args[0], self.load_list(args[1])
        for repo in repos:
            url = "https://api.bitbucket.org/2.0/repositories/%s/%s/deploy-keys" % (org, repo)
            for j in self.get_api_json(url):
                if j is None: continue
                if not 'values' in j: continue
                for key in j['values']:
                    yield key

    def get_repos(self, args):
        org = args[0]
        self.csvw = csv.writer(sys.stdout, quoting=csv.QUOTE_NONNUMERIC)
        self.csvw.writerow( [ "slug","name","created_on","updated_on","has_issues","has_wiki" ] )
        for repo in self._repos(args):
            self.csvw.writerow( [ 
                repo['slug'], repo['name'], repo['created_on'], 
                repo['updated_on'], repo['has_issues'], repo['has_wiki'] 
            ] )

    def get_repo_deploy_keys(self, args):
        org, repos = args[0], self.load_list(args[1])
        self.csvw = csv.writer(sys.stdout, quoting=csv.QUOTE_NONNUMERIC)
        self.csvw.writerow( [ "org", "repo", "id", "type", "created_on", "last_used", "public_key", "comment" ] )
        for key in self._repo_deploy_keys(args):
            self.csvw.writerow( [ 
                org, key['repository']['name'], key['id'], key['type'], key['created_on'], key['last_used'],
                key['key'].rstrip(), key['comment'].rstrip(), key['label'].rstrip() 
            ] )

    def delete_repo_deploy_key(self, args):
        org, repo, _id = args[0], args[1], args[2]
        url = "https://api.bitbucket.org/2.0/repositories/%s/%s/deploy-keys/%s" % (org, repo, _id)
        j = self.delete_api_json(url)
        print("org='%s' repo='%s': Deleted key '%s'" % (org, repo, _id))

    def delete_repo_deploy_keys(self, args):
        opts, argv = getopt.getopt(args, "bacl")
        before, after, creation, lastused = False, False, False, False
        for o, a in opts:
            if   o == '-b':  before   = True
            elif o == '-a':  after    = True
            elif o == '-c':  creation = True
            elif o == '-l':  lastused = True

        if (before == False and after == False) or (before == True and after == True):
            print("Error: you must specify one of -b or -a")
            exit(1)
        if creation == False and lastused == False:
            print("Error: you must specify one of -c or -l")
            exit(1)

        org, repos = argv[0], self.load_list(argv[1])
        dt = dateutil.parser.parse(argv[2])
        now = datetime.now(tz.UTC)
        for key in self._repo_deploy_keys( argv ):
            repo = key['repository']['name']
            creation_d = dateutil.parser.parse(key['created_on']) if key['created_on'] != None else None
            lastused_d = dateutil.parser.parse(key['last_used']) if key['last_used'] != None else None
            delete=False
            if before:
                if creation and creation_d < dt:
                    print("org='%s' repo='%s': key id '%s' created before DT '%s'; deleting" % (org, repo, key['id'], dt))
                    delete=True
                elif lastused_d != None and lastused and lastused_d < dt:
                    print("org='%s' repo='%s': key id '%s' last used before DT '%s'; deleting" % (org, repo, key['id'], dt))
                    delete=True
            elif after:
                if creation and creation_d > dt:
                    print("org='%s' repo='%s': key id '%s' created after DT '%s'; deleting" % (org, repo, key['id'], dt))
                    delete=True
                elif lastused_d != None and lastused and lastused_d > dt:
                    print("org='%s' repo='%s': key id '%s' last used after DT '%s'; deleting" % (org, repo, key['id'], dt))
                    delete=True
            if delete == True:
                self.delete_repo_deploy_key([org, repo, key['id']])

def usage():
    usage_str = """Usage: %s COMMAND [OPTIONS]

Commands:

get_repos ORG
                    - Gets all repositories for ORG. Prints out a CSV file.

get_repo_deploy_keys ORG REPO
                    - Gets all deploy keys for a repository. REPO can be a single repository,
                      or a "file:///path/to/a/file" to read repositories from, or "-" to read
                      repositories line-by-line from standard input. Prints out a CSV file.

delete_repo_deploy_key ORG REPO ID
                    - Deletes a deploy key ID from ORG/REPO.

delete_repo_deploy_keys [OPTIONS] ORG REPO DATETIME
                    - Deletes any deploy keys in ORG/REPO based on OPTIONS, before or after
                      a DATETIME.
                      REPO can be a single repository, or a "file:///path/to/a/file" to read
                      repositories from, or "-" to read repositories line-by-line from standard
                      input.
                      The following OPTIONS modify what keys to select based on DATETIME:
                        -b      Keys created before the DATETIME
                        -a      Keys created after the DATETIME
                        -c      DATETIME refers to the creation date
                        -l      DATETIME refers to the last used date

""" % sys.argv[0]
    print(usage_str)
    exit(1)

def main():
    o = ManageBitbucket()

    if len(sys.argv) < 2:
        usage()
    elif sys.argv[1] == "get_repos":
        o.get_repos(sys.argv[2:])
    elif sys.argv[1] == "get_repo_deploy_keys":
        o.get_repo_deploy_keys(sys.argv[2:])
    elif sys.argv[1] == "delete_repo_deploy_key":
        o.delete_repo_deploy_key(sys.argv[2:])
    elif sys.argv[1] == "delete_repo_deploy_keys":
        o.delete_repo_deploy_keys(sys.argv[2:])
    else:
        usage()

if __name__ == "__main__":
    main()
