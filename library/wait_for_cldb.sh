#!/bin/bash
#
# (c) 2016 MapR Technologies, Inc. All Rights Reserved.
#
# Deployer
#
# @file:    wait_for_cldb.sh
##########################################################

LOG=/tmp/wait_for_cldb.log

#	Ansbile Integration: if $1 is passed in, we assume it is the 
#	ansible argument passing logic (a dump of key-value pairs).  
#	This sed expression parses it out.
#		No, I'm not that good a sed programmer; found this example
#		on the Ansible web site.	DBT  30-Oct-2013

if [ -n "${1}"  -a  -f "${1}" ] ; then
    eval $(sed -e "s/\s?\([^=]+\)\s?=\s?\(\x22\([^\x22]+\)\x22|\x27\([^\x27]+\)\x27|\(\S+\)\)\s?/\1='\2'/p" $1)

fi

#	We expect a simple argument list for this script :
#		MAX_WAIT	# maximum wait time in seconds
MAX_WAIT=${MAX_WAIT:-600}
MAPR_HOME=${MAPR_HOME:-/opt/mapr}
MAPR_USER=${MAPR_USER:-mapr}
MAPR_GROUP=${MAPR_USER:-mapr}

CMSTR_CMD="timeout -s HUP 5s $MAPR_HOME/bin/maprcli node cldbmaster -noheader 2> /dev/null"

# It's a real kludge to handle this check when security is enabled.
# Rather than force the use of the mapr user password here, we'll
# do the wait ONLY if the user can access the core user ticket.
#
# Since it can take some time for the ticket to be generated, we'll
# wait up to 5 minutes here before the CLDB check
#
grep -q "secure=true" $MAPR_HOME/conf/mapr-clusters.conf
if [ $? -eq 0 ] ; then
    USERTICKET=${MAPR_HOME}/conf/mapruserticket

    TICKET_WAIT=300
    [ $TICKET_WAIT -gt $MAX_WAIT ] && TICKET_WAIT=$MAX_WAIT

    SWAIT=$TICKET_WAIT
    STIME=3
    test -r $USERTICKET 
    while [ $? -ne 0  -a  $SWAIT -gt 0 ] ; do
        sleep $STIME
        SWAIT=$[SWAIT - $STIME]

        test -r $USERTICKET 
    done
    if [ ! -r $USERTICKET ] ; then
        echo "{\"changed\":true, \"msg\":\"CLDB launched, but no privileges to check CLDB status\"}"
        exit 0
    fi

    # Decrease MAX_WAIT time
    TICKET_WAIT=$[TICKET_WAIT - $SWAIT]
    if [ $MAX_WAIT -gt $TICKET_WAIT ] ; then
        MAX_WAIT=$[MAX_WAIT - $TICKET_WAIT]
    fi

    MAPR_TICKETFILE_LOCATION=${USERTICKET}
    export MAPR_TICKETFILE_LOCATION
fi

# One last thing ... we REALLY need JAVA_HOME set for maprcli to work
# As a security measure, we'll just load the env.sh script
#
. $MAPR_HOME/conf/env.sh

SWAIT=$MAX_WAIT
STIME=5
$CMSTR_CMD 2>> $LOG
while [ $? -ne 0  -a  $SWAIT -gt 0 ] ; do
    echo "CLDB not found; will wait for $SWAIT more seconds" | tee -a $LOG
    sleep $STIME
    SWAIT=$[SWAIT - $STIME]

    $CMSTR_CMD 2>> $LOG
done

# Yes, it's stupid to make this call again ... I just couldn't easily
# make the wait loop work without too many dependencies on the output
# syntax of maprcli; safer to just use return code.
if [ $? -eq 0 ] ; then
    cmstr=`$CMSTR_CMD | awk '{print $NF}'`
    echo "{\"changed\":true, \"msg\":\"CLDB on-line. CLDB master is $cmstr\"}"
else
    echo "{\"failed\":true, \"msg\":\"MapR CLDB failed to come on line within $MAX_WAIT seconds\"}"
fi

exit 0

