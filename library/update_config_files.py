#!/usr/bin/env python

from __future__ import print_function
import os
import sys
import shutil

LOG_FILE = "/tmp/update_config_files.log"

with open(LOG_FILE, 'a') as logf:
    print("CHECKING for Config Files that need Updates", file=logf)
    cfg_vars = {}
    with open(sys.argv[1]) as arg_file:
        for line in arg_file:
            pairs = line.split()
            for pair in pairs:
                name, val = pair.partition("=")[::2]
                cfg_vars[name.strip()] = val.strip()

    CFG_OLD_MAP = {"401": "/opt/mapr/hadoop/hadoop-2.4.1.bak/etc/hadoop"}
    CFG_NEW_MAP = {"402": "/opt/mapr/hadoop/hadoop-2.5.1/etc/hadoop"}

    print("Contents of cfg_vars {0}".format(cfg_vars), file=logf)

    if "MAPR_VERSION" in cfg_vars:
        if cfg_vars["MAPR_VERSION"] not in CFG_OLD_MAP:
            print("Unsupported Version: {0}".filter(cfg_vars["MAPR_VERSION"]), file=logf)
            print("{\"failed\":true, \"msg\":\"Unsupported version\"}")
            sys.exit(0)
    else:
        print("{\"failed\":true, \"msg\":\"Unknown MapR Version\"}")
        sys.exit(0)

    if "MAPR_UPGRADE_VERSION" in cfg_vars:
        if cfg_vars["MAPR_UPGRADE_VERSION"] not in CFG_NEW_MAP:
            print("Unsupported Upgrade Version: {0}".filter(cfg_vars["MAPR_UPGRADE_VERSION"]), file=logf)
            print("{\"failed\":true, \"msg\":\"Unsupported Upgrade version\"}")
            sys.exit(0)
    else:
        print("{\"failed\":true, \"msg\":\"Unknown MapR Upgrade Version\"}")
        sys.exit(0)

    try:
        src = CFG_OLD_MAP[cfg_vars["MAPR_VERSION"]]
        dst = CFG_NEW_MAP[cfg_vars["MAPR_UPGRADE_VERSION"]]
        src_files = os.listdir(src)

        for file_name in src_files:
            full_file_name = os.path.join(src, file_name)
            if os.path.isfile(full_file_name):
                shutil.copy(full_file_name, dst)

    except (IOError, os.error), why:
        print("{\"failed\":true, \"msg\":\"Unable to copy config files {0}\"}".format(str(why)))
        sys.exit(0)

    print("{\"changed\":true, \"msg\":\"Configuration files updated successfully.\"}")
    sys.exit(0)

print("{\"changed\":false}")
sys.exit(0)
