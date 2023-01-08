#!/usr/bin/env python3
# circleci-manage.py
# Copyright (C) 2022 Peter W <31324861+peterwwillis@users.noreply.github.com>

import os
import sys
import csv
import requests


headers = {
        'Circle-Token': os.environ["CIRCLE_TOKEN"]
}

class ManageCircleSecrets:
    csvw = None

    def post_api_json(self, url, payload):
        my_headers = headers.copy()
        my_headers['Content-Type'] = 'application/json'
        try:
            response = requests.post(url, headers=my_headers, data=payload)
        except:
            print("Error deleting page '%s': '%s'" % (url, response), file=sys.stderr)
            return(None)
        return response.json()

    def delete_api_json(self, url):
        try:
            response = requests.api.delete(url, headers=headers)
        except:
            print("Error deleting page '%s': '%s'" % (url, response), file=sys.stderr)
            return(None)
        return response.json()

    def get_api_json(self, url):
        next_page_token = None
        next_page_url = url[:]
        while next_page_url is not None:
            try:
                response = requests.get(next_page_url, headers=headers)
            except:
                print("Error getting page '%s'" % next_page_url, file=sys.stderr)
                return(None)

            page_json = response.json()
            yield page_json

            next_page_token = page_json.get('next_page_token', None)
            if next_page_token != None:
                next_page_url = url[:] + "&page-token=%s" % next_page_token
            else:
                next_page_url = None

    @staticmethod
    def load_list(arg):
        # arg can be a literal string, or a "file:///path/to/a/file", or "-" to read from stdin.
        # returns a list.
        args=[arg]
        if arg.startswith("file://"):
            with open(arg[7:]) as f:
                argss = f.read().splitlines()
        elif arg == "-":
            args = sys.stdin.read().splitlines()
        return args

    def get_project_vars(self, args):
        vcs, org, projects = args[0], args[1], self.load_list(args[2])
        self.csvw = csv.writer(sys.stdout, quoting=csv.QUOTE_NONNUMERIC)
        self.csvw.writerow( [ "vcs", "org", "project", "name", "value" ] )
        for proj in projects:
            url = "https://circleci.com/api/v2/project/%s/%s/%s/envvar" % (vcs, org, proj)
            for j in self.get_api_json(url):
                if j is None: continue
                if not 'items' in j: continue
                for key in j['items']:
                    self.csvw.writerow( [ vcs, org, proj, key['name'], key['value'] ] )

    def get_checkout_keys(self, args):
        # project can be a single project, or a "file:///path/to/a/file", or "-" to read from stdin
        vcs, org, projects = args[0], args[1], self.load_list(args[2])
        self.csvw = csv.writer(sys.stdout, quoting=csv.QUOTE_NONNUMERIC)
        self.csvw.writerow( [ "vcs", "org", "project", "key_type", "key_preferred", "key_created_at", "public_key", "key_fingerprint" ] )
        for proj in projects:
            url = "https://circleci.com/api/v2/project/%s/%s/%s/checkout-key" % (vcs, org, proj)
            for j in self.get_api_json(url):
                if j is None: continue
                if not 'items' in j: continue
                for key in j['items']:
                    self.csvw.writerow( [ vcs, org, proj, key['type'], key['preferred'], key['created_at'], key['public_key'].rstrip(), key['fingerprint'] ] )

    def create_checkout_key(self, args):
        vcs, org, project = args[0], args[1], args[2]
        url = "https://circleci.com/api/v2/project/%s/%s/%s/checkout-key" % (vcs, org, project)
        j = self.post_api_json(url, '{"type":"deploy-key"}')
        if 'fingerprint' in j:
            print("vcs='%s' org='%s' project='%s': Created key '%s'" % (vcs, org, project, j['fingerprint']))
        else:
            print("vcs='%s' org='%s' project='%s': Failed to create fingerprint: '%s'" % (vcs, org, project, j))

    def delete_checkout_key(self, args):
        vcs, org, project, fingerprint = args[0], args[1], args[2], args[3]
        url = "https://circleci.com/api/v2/project/%s/%s/%s/checkout-key/%s" % (vcs, org, project, fingerprint)
        j = self.delete_api_json(url)
        print("vcs='%s' org='%s' project='%s': Deleted key '%s'" % (vcs, org, project, fingerprint))

    def rotate_checkout_key(self, args):
        vcs, org, project, fingerprint = args[0], args[1], args[2], args[3]
        self.delete_checkout_key(args)
        self.create_checkout_key(args)


def usage():
    usage_str = """Usage: %s COMMAND [OPTIONS]

Commands:

get_checkout_keys VCS ORG PROJECT
                    -   Gets all checkout keys for a project. PROJECT can be a single
                        project, or a "file:///path/to/a/file" to read projects from,
                        or "-" to read projects line-by-line from standard input.
                        Prints out a CSV file.

create_checkout_key VCS ORG PROJECT
                    -   Creates a deploy key in VCS / ORG / PROJECT

delete_checkout_key VCS ORG PROJECT FINGERPRINT
                    -   Deletes a checkout key FINGERPRINT

rotate_checkout_key VCS ORG PROJECT FINGERPRINT
                    -   Deletes a checkout key FINGERPRINT, then creates a new one.

get_project_vars VCS ORG PROJECT
                    -   List all the project-specific environment variables.
                        Prints out a CSV file.
""" % sys.argv[0]
    print(usage_str)
    exit(1)

def main():
    o = ManageCircleSecrets()

    if len(sys.argv) < 2:
        usage()
    elif sys.argv[1] == "get_checkout_keys":
        o.get_checkout_keys(sys.argv[2:])
    elif sys.argv[1] == "create_checkout_key":
        o.create_checkout_key(sys.argv[2:])
    elif sys.argv[1] == "delete_checkout_key":
        o.delete_checkout_key(sys.argv[2:])
    elif sys.argv[1] == "rotate_checkout_key":
        o.rotate_checkout_key(sys.argv[2:])
    elif sys.argv[1] == "get_project_vars":
        o.get_project_vars(sys.argv[2:])
    else:
        usage()

if __name__ == "__main__":
    main()
