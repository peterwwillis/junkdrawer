#!/usr/bin/env python3
# jenkins-run-job-with-parameter-defaults.py - Run a Jenkins job with parameters

import sys, json, subprocess

def cmdout(args):
    print("Running command '%s'" % args)
    p1 = subprocess.Popen( args , stdout=subprocess.PIPE)
    return p1.communicate()[0]

def usage(reason=None):
    if reason != None: print("Error: %s\n\n" % reason)
    print("Usage: %s USER JOBURL JSONFILE\n\nUses USER to authenticate to a jenkins instance, gets JOBURL, figures out which parameters are mandatory, inserts any key:value pairs from JSONFILE, and POSTs it back to JOBURL.\n" % sys.argv[0])
    print("Example:\n\t%s myuser:mytoken https://foobar.com/job/00_admin/job/01_create-jenkins-team-credentials/ my-params.json\n" % sys.argv[0])
    exit(1)

if len(sys.argv) != 4:
    usage()

user, joburl, jsonfile = sys.argv[1], sys.argv[2], sys.argv[3]
jsonjoburl = "%s/api/json" % joburl
curl = [ "curl", "-sL", "-u", user, jsonjoburl ]
print("Getting job details ...")
j = json.loads( cmdout(curl) )

required = []
for i in j["property"]:
    for a in i["parameterDefinitions"]:
        if a["defaultParameterValue"]["value"] == "":
            #print("Empty value found for key '%s'" % a["name"])
            required.append(a["name"])

print("Found required build values: '%s'" % required)

with open(jsonfile) as f:
    form = ''
    j2 = json.load(f)
    for k, v in j2.items():
        form = "%s&%s=%s" % (form, k, v)
    # Fill in missing requires as "N/A"
    for r in required:
        if not r in j2:
            form = "%s&%s=%s" % (form, r, "N/A")
    newurl = "%s/buildWithParameters" % joburl
    curl2 = [ "curl", "-sL", "-u", user, "--data", form, newurl ]
    print("Submitting build with parameters: %s" % form)
    print( cmdout( curl2 ) )

