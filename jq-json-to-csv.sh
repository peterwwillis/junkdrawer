#!/usr/bin/env sh
# jq-json-to-csv.sh - convert JSON document into CSV file
#
# Usage: jq-json-to-csv.sh [jq options] [FILE]
#
# Your JSON document should look like this:
#
#     [
#       { "foo": "one",   "bar": "two" },
#       { "foo": "three", "bar": "four" }
#     ]
#
#  If your JSON document is actually a stream of JSON documents
#  (not enclosed in an array), just add the '-s' option before
#  your json file to enable slurp mode.

jq -r '(.[0] | keys_unsorted) as $keys | $keys, map([.[ $keys[] ]])[] | @csv' "$@"

