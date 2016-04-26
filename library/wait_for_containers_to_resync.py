#!/usr/bin/env python

from __future__ import print_function
import shlex
import subprocess
import sys
import time

cmd = "/opt/mapr/server/mrconfig info containers resync local"
LOG_FILE = "/tmp/wait_for_containers_to_resync.log"

logf = open(LOG_FILE, 'w')

try:
    while True:
        # Some times alarm's wont appear instantly.
        print("Waiting for 120 seconds...", file=logf)
        logf.flush()
        time.sleep(120)
        print("Done waiting", file=logf)
        logf.flush()
        p = subprocess.Popen(shlex.split(cmd), stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        print("Done running command", file=logf)
        datastr = p.stdout.read()
        p.wait()
        print("SYNC INFO: {0}".format(datastr), file=logf)
        logf.flush()
        if p.returncode != 0:
            print("COMMAND returns a non-zero status: {0}".format(p.returncode), file=logf)
            continue
        if datastr.strip() != "":
            time.sleep(120)
            print("changed=True msg=\"Containers all in sync\"")
            sys.exit(0)
        else:
            print("changed=True msg=\"Containers all in sync\"")
            sys.exit(0)
except Exception, e:
    print(e, file=logf)
    print("failed=True msg=\"Exception occured\"")
    sys.exit(1)
