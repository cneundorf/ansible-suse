#!/bin/bash
#
# (c) 2016 MapR Technologies, Inc. All Rights Reserved.
#
# Deployer
#
# @file:    wait_for_zk_nodes.sh
##########################################################

LOG=/tmp/wait_for_zk_nodes.log
[ `id -u` -ne 0 ] && SUDO="/usr/bin/sudo"

#	Ansbile Integration: if $1 is passed in, we assume it is the 
#	ansible argument passing logic (a dump of key-value pairs).  
#	This sed expression parses it out.
#		No, I'm not that good a sed programmer; found this example
#		on the Ansible web site.	DBT  30-Oct-2013

if [ -n "${1}"  -a  -f "${1}" ] ; then
    eval $(sed -e "s/\s?\([^=]+\)\s?=\s?\(\x22\([^\x22]+\)\x22|\x27\([^\x27]+\)\x27|\(\S+\)\)\s?/\1='\2'/p" $1)

fi

#	We expect a simple argument list for this script :
#		ZK_NODES	# comma-separated list of ZK hostnames nodes
#		MAX_WAIT	# maximum wait time in seconds (optional)
MAX_WAIT=${MAX_WAIT:-600}
THIS_HOST=`/bin/hostname -s`

# Not sure how to handle this error.  For now, just bail
if [ -z "${ZK_NODES:-}" ] ; then
    echo "{\"changed\":false, \"msg\":\"No Zookeeper nodes specified; will not wait\"}"
    exit 0
fi

# Don't wait for other Zookeepers if we are a Zookeeper ourself
for zn in ${ZK_NODES//,/ } ; do
    # No need to check "ourself" for this test
    zn_short=${zn%.*}
    if [ "$zn" = "$THIS_HOST" ] ; then
        echo "{\"changed\":false, \"msg\":\"Zookeeper service configured on this node; will not wait\"}"
        exit 0
    fi
done


echo "Will wait up to $SWAIT seconds for ZK service at $ZK_NODES" | tee -a $LOG

# We'll really wait for a quorum of ZK nodes
NUM_ZK=`echo $ZK_NODES | awk -F ',' '{print NF}'`
ZK_QUORUM=$[NUM_ZK/2]
[ $[ZK_QUORUM*2] -lt $NUM_ZK ] && ZK_QUORUM=$[ZK_QUORUM+1]

ZK_FOUND=0
SWAIT=$MAX_WAIT
STIME=5
NC=nc

# On SuSE, use netcat instead of nc
which netcat > /dev/null 2>&1
if [ $? -eq 0 ]; then
    NC=netcat
fi

while [ $ZK_FOUND -lt $ZK_QUORUM  -a  $SWAIT -gt 0 ] ; do
    echo "Looking for ZK nodes; will wait for $SWAIT more seconds" | tee -a $LOG

    for zn in ${ZK_NODES//,/ } ; do
        zn_short=${zn%.*}
        if [ "$zn" == "$THIS_HOST" ] ; then
            ZK_FOUND=$[ZK_FOUND+1]
        else
            echo " checking $zn" | tee -a $LOG
            echo "ruok" | ${SUDO:-} $NC $zn 5181
            if [ $? -eq 0 ] ; then
                echo "   was found" | tee -a $LOG
                ZK_FOUND=$[ZK_FOUND+1]
            else
                echo "   not found" | tee -a $LOG
            fi
        fi
    done

    sleep $STIME
    SWAIT=$[SWAIT - $STIME]
done

if [ $ZK_FOUND -ge $ZK_QUORUM ] ; then
    echo "{\"changed\":true, \"msg\":\"Zookeeper service on-line\"}" | tee -a $LOG
else
    echo "{\"failed\":true, \"msg\":\"Failed to detect MapR Zookeeper within $MAX_WAIT seconds.  Confirm that the mapr-zookeeper service is running on $ZK_NODES and that no external filrewall is blocking port 5181.\"}" | tee -a $LOG
fi

exit 0

