#!/usr/bin/env python3
# jenkins-trigger-paramaterized-build.py - Run a Jenkins parameterized build

import sys, json, argparse

class TriggerJob:
    args = None
    base_url = None
    kv = {}
    curl_cmd = [ "curl" ]
    curl_user = None

    def __init__(self, **karg):
        self.parse_args( **karg )

    def parse_args(self, server_url=None, files=None):
        if files != None:
            self.args = files
        if server_url != None:
            self.base_url = server_url
        for arg in self.args:
            print("Opening JSON file '%s'" % arg)
            with open(arg) as f:
                j = json.load(f)
                self.kv[arg] = {}
                for k in j:
                    #print("Found key '%s' = '%s'" % (k, j[k]))
                    self.kv[arg][k] = j[k]

    def user(self, u=None):
        if u != None: self.curl_user = u
        return self.curl_user

    def curl(self, arg):
        cmd = self.curl_cmd.copy()
        if self.user() != None:
            cmd.extend( [ "-u", self.curl_user ] )

        if type(arg) == type([]):
            cmd.extend( arg )
        else:
            cmd.extend( [ arg ] )

        print("Running command '%s'" % cmd)

    def buildWithParams(self):
        baseurl = self.base_url

        for f, d in self.kv.items():
            if not '__JOBURL__' in d:
                usage("Error: please add a key '__JOBURL__' in your JSON file")

            url = "%s%s/buildWithParameters" % (baseurl, d['__JOBURL__'])
            del d['__JOBURL__']

            form = ''
            for k,v in d.items():
                form = "%s&%s=%s" % (form, k, v)

            self.curl( [ "--data", form, url ] )

def usage(blah=None):
        if blah != None: print("%s\n" % blah)
        print("Usage: %s [OPTIONS] JENKINS_SERVER_URL PARAMETER_JSON [..]\n\nGiven a jenkins server URL, parses a JSON file which contains a list of key:value pairs to pass to a paramaterized job, and uses the REST API to run the job.\n\nThe JSON file may contain the following key-values to help:\n\t__JOBURL__\n\nOptions:\n\t-u user:pass\t\tTells CURL the username and password to use.\n")
        exit(1)

def main(args):
    parser = argparse.ArgumentParser()
    parser.add_argument('-u', '--user')
    parser.add_argument('SERVER_URL')
    parser.add_argument('JSON_FILE', nargs='+')
    args = parser.parse_args()
    
    tj = TriggerJob( server_url=args.SERVER_URL, files=args.JSON_FILE )
    tj.user(args.user)
    tj.buildWithParams()


if __name__ == "__main__":
    main(sys.argv[1:])

