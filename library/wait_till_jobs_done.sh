#!/bin/bash
#
# (c) 2016 MapR Technologies, Inc. All Rights Reserved.
#
#
#
########################################################

LOG=/tmp/wait_till_jobs_done.log

# This is an absolute hacky way to determing if a node is running an MR job.
# Unfortunately, at this time there is no proper api to query this information
CMDSTR="pgrep -f attempt_"

MAX_TRY=60
CUR_TRY=0
while :
do
    sleep 1
    CUR_TRY=$((CUR_TRY + 1))
    $CMDSTR >>/dev/null
    if [ $? -eq 1 ]; then
        if [ $CUR_TRY -eq $MAX_TRY ]; then
            echo "changed=True msg=\"No Jobs running\""
            exit 0
        fi
        continue
    else
        CUR_TRY=0 #Reset
        echo "Job still running on the node. Sleeping" >> $LOG
        sleep 1
    fi
done

