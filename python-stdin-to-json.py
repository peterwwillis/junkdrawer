#!/usr/bin/env python3
# Dump standard input stream as a JSON-formatted output
import sys,json;json.dump(sys.stdin.read(), sys.stdout)
