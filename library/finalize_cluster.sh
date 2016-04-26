#!/bin/bash
#
# (c) 2016 MapR Technologies, Inc. All Rights Reserved.
#
# Deployer
#
# @file:    finalize_cluster.sh
##########################################################
#
# We don't do too much to handle errors ... these are all
# "extra" steps that just simplify the cluster post-installation.
#

LOG=/tmp/finalize_cluster.log

# Returns 1 if volume comes on line within 5 minutes
# This is not ideal, but it's the only safe way to add
# the necessary volumes below without recreating the work
# of createsystemvolumes.sh
#
wait_for_mapr_volume() {
    VOL=$1
    VOL_ONLINE=0
    [ -z "${VOL}" ] && return $VOL_ONLINE

    echo "Waiting for $VOL volume to come on line" >> $LOG
    i=0
    while [ $i -lt ${MAX_WAIT} ]
    do
        timeout -s HUP 10s maprcli volume info -name $VOL &> /dev/null
        if [ $? -eq 0 ] ; then
            echo " ... success !!!" >> $LOG
            VOL_ONLINE=1
            i=9999
            break
        fi

        sleep 3
        i=$[i+3]
    done

    return $VOL_ONLINE
}


#	Ansbile Integration: if $1 is passed in, we assume it is the
#	ansible argument passing logic (a dump of key-value pairs).
#	This sed expression parses it out.
#		No, I'm not that good a sed programmer; found this example
#		on the Ansible web site.	DBT  30-Oct-2013

if [ -n "${1}"  -a  -f "${1}" ] ; then
    eval $(sed -e "s/\s?\([^=]+\)\s?=\s?\(\x22\([^\x22]+\)\x22|\x27\([^\x27]+\)\x27|\(\S+\)\)\s?/\1='\2'/p" $1)
fi

MAX_WAIT=${MAX_WAIT:-300}
MAPR_HOME=${MAPR_HOME:-/opt/mapr}
MAPR_USER=${MAPR_USER:-mapr}

echo "-----------" >> $LOG
echo "MAPR_HOME=$MAPR_HOME" >> $LOG
echo "MAPR_USER=$MAPR_USER" >> $LOG

# One last thing before we start ... we REALLY need JAVA_HOME set
# for maprcli to work As a security measure, we'll just load the
# env.sh
#
. $MAPR_HOME/conf/env.sh

MapR_Success="Successfully installed MapR"
[ -f $MAPR_HOME/MapRBuildVersion ] && \
    MapR_Success="${MapR_Success} version `cat $MAPR_HOME/MapRBuildVersion`"
MapR_Success="${MapR_Success} on node `hostname -s`."
MapR_Success="${MapR_Success}  Use the maprcli command to further manage the system."


MAPRCLI=`which maprcli 2> /dev/null`
if [ -z "${MAPRCLI}" ] ; then
    echo "{\"changed\":false, \"msg\":\"maprcli command not found.  This is likely a client-only installation\"}"
    exit 0
fi

# Run the finalize steps ONLY on a CLDB node
if [ ! -f $MAPR_HOME/roles/cldb ] ; then
    echo "{\"changed\":true, \"msg\":\"$MapR_Success\"}"
    exit 0
fi

grep -q "secure=true" $MAPR_HOME/conf/mapr-clusters.conf
if [ $? -eq 0 ] ; then
    USERTICKET=${MAPR_HOME}/conf/mapruserticket
    if [ ! -r $USERTICKET ] ; then
        echo "{\"changed\":false, \"msg\":\"No security ticket available to execute maprcli commands\"}"
        exit 0
    fi

    MAPR_TICKETFILE_LOCATION=${USERTICKET}
    export MAPR_TICKETFILE_LOCATION
fi

$MAPRCLI acl edit -type cluster -user ${MAPR_USER}:fc

wait_for_mapr_volume users
USERS_ONLINE=$?

if [ ${USERS_ONLINE} -eq 0 ] ; then
    echo "WARNING: user volume did not come on-line" >> $LOG
else
    HOME_VOL=${MAPR_USER}_home

    maprcli volume info -name $HOME_VOL &> $LOG
    if [ $? -ne 0 ] ; then
        echo "Creating home volume for ${MAPR_USER}" >> $LOG
        su $MAPR_USER -c "maprcli volume create -name ${HOME_VOL} -path /user/${MAPR_USER} -replicationtype low_latency"
    fi
fi

echo $MapR_Success >> $LOG
echo "{\"changed\":true, \"msg\":\"$MapR_Success\"}"

exit 0
