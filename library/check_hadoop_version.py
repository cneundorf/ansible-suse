#!/usr/bin/env python

from __future__ import print_function
import json
import shlex
import subprocess
import sys

cmd = "maprcli cluster mapreduce get -json"
LOG_FILE = "/tmp/check_hadoop_version.log"

logf = open(LOG_FILE, 'a')

try:
    p = subprocess.Popen(shlex.split(cmd), stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    datastr = p.stdout.read()
    p.wait()
    print("HADOOP VERSION INFO: {0}".format(datastr), file=logf)
    if p.returncode != 0:
        # This is most likely a 3.x system, where the culster mapreduce isn't available"
        print("{\"changed\":false, \"default_mode\":\"classic\"}")
        sys.exit(0)
    data = json.loads(datastr)
    if u'status' in data and data[u'status'] == u'OK':
        mode = data[u'data'][0][u'default_mode']
        print("{\"changed\":true, \"default_mode\":\"{0}\"}".format(mode))
        sys.exit(0)
    print("{\"changed\":false, \"default_mode\":\"classic\"}")
    sys.exit(0)
except Exception, e:
    print(e, file=logf)
    # We do this as a fallback.
    print("{\"changed\":false, \"default_mode\":\"classic\"}")
    sys.exit(0)
