#!/usr/bin/env python3

""" 
    Use a Python template and CSV to generate a directory of files.
    Each row of the CSV results in a new file.
    The CSV's column headings are keys, the row entries are values,
    and the key=value pairs are passed to the Template's substitution function.
"""

import csv
import sys
import os
from string import Template

class IterCsv(object):
    rows=[]
    templatetxt=None
    outdir=None

    def __init__(self, csvfile=None, templatefile=None, outdir=None):
        """ Pass csvfile, templatefile, and outdir.
            Checks if outdir exists, and reads in csvfile and templatefile.
            csvfile must contain a heading row.
        """
        if not os.path.isdir(outdir):
            raise Exception("Error: directory '%s' does not exist" % outdir)
        self.outdir = outdir
        with open(csvfile) as f:
            csvreader = csv.DictReader(f)
            lineno=0
            for row in csvreader:
                if lineno == 0:
                    lineno += 1
                    continue
                self.rows.append(row)
        with open(templatefile, "r") as fh:
            self.templatetxt = fh.read()

    def process_rows(self):
        """ Takes each csvfile row and generates an output file in outdir based
            on templatefile text.
        """
        c=0
        rowlen = len(self.rows)
        for row in self.rows:
            t = Template(self.templatetxt)
            # ugly hack: add the precision for file number using the
            # length of digits for the number of rows
            fmtstr = "%s/row.%." + str(len(str(rowlen))) + "i.out"
            outfilename = fmtstr % (self.outdir, c)
            with open(outfilename, "w") as f:
                txt = t.substitute(row)
                f.write( txt )
            c += 1

if __name__ == "__main__":
    if len(sys.argv) < 4:
        print("Usage: %s CSVFILE TEMPLATE OUTDIR" % sys.argv[0])
        exit(1)
    obj = IterCsv(csvfile=sys.argv[1], templatefile=sys.argv[2], outdir=sys.argv[3])
    obj.process_rows()

