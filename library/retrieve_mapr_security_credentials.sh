#!/bin/bash
#
# (c) 2016 MapR Technologies, Inc. All Rights Reserved.
#
# Deployer
#
# @file:    retrieve_credentials.sh
##########################################################

LOG=/tmp/retrieve_credentials.log
[ `id -u` -ne 0 ] && SUDO=sudo

# Helper functions for exiting properly for Ansible
#	exitSucess <msg>   # eg ansible_exit "OK"
#	exitFailure <msg>   # eg ansible_exit "Unable to create <foo>"
#
function exitSuccess() {
    if [ -n ${ANSIBLE_PARENT} ] ; then
        echo "{\"changed\":true, \"msg\":\"$1\"}"
    else
        echo "$1"
    fi
    exit 0
}

function exitFailure() {
    if [ -n ${ANSIBLE_PARENT} ] ; then
        echo "{\"failed\":true, \"msg\":\"$1\"}"
        exit 0
    else
        echo "$1"
        exit 1
    fi
}

# exec_and_retry code along with retrieve_mapr_security_credentials
# stolen from MapR EMR bootstrap action script.
status_wait_time=3
num_retries=99

#
# ${1}: command to execute and retry
# ${2}: error message
#
exec_and_retry()
{
    local i=0
    eval ${1}
    while [ $? -ne 0 ] && [ $i -lt ${num_retries} ] ; do
        sleep ${status_wait_time}
        i=$[i+1]
        eval ${1}
    done

    if [ $i -eq ${num_retries} ] ; then
        echo "ERROR: ${2}" >> $LOG # ${2} is the error message
        echo "retried for ${num_retries} * ${status_wait_time} seconds" >> $LOG
        if [ ${num_retries} -ge 100 ] ; then
            exitFailure "$2"
        fi
    fi
}

# When MapR Security is enabled, we must retrieve the credentials
# from the Master node BEFORE running configure.sh.   
#
# Failing to retrieve the credentials is a critical error, 
# because we cannot run configure.sh and start the cluster 
# without them.
retrieve_mapr_security_credentials() 
{
    [ ${LOG_TIMING:-0} -ne 0 ] && \
        echo "  Entering retrieve_mapr_security_credentials  at "`date +"%H:%M:%S"`

    # The presence of maprserverticket and ssl_truststore on the master
    # is our confirmation that the credentials are completely generated 
    #	Yes, this is "boot and suspenders", but it is not clear
    #	that there is any consistency to the order that the
    #	keys are generated on the master node.

    exec_and_retry \
        "ssh -i /home/${MAPR_USER}/.ssh/installer_key -n -o StrictHostKeyChecking=no ${MAPR_USER}@${SEC_MASTER} ls $MAPR_HOME/conf/maprserverticket" \
        "No master security ticket found"

    exec_and_retry \
        "ssh -i /home/${MAPR_USER}/.ssh/installer_key -n -o StrictHostKeyChecking=no ${MAPR_USER}@${SEC_MASTER} ls $MAPR_HOME/conf/ssl_truststore" \
        "No ssl_truststore found"

    # Copying these over is a kludge, since we only have
    # clean ssh back to the Master node as the MapR user
    #
    # TO BE DONE : better error checking on these retrievals
    scp -i /home/${MAPR_USER}/.ssh/installer_key -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ${MAPR_USER}@${SEC_MASTER}:$MAPR_HOME/conf/maprserverticket $HOME
    chown -R ${MAPR_USER}:${MAPR_GROUP} $HOME/maprserverticket
    ${SUDO:-} mv $HOME/maprserverticket $MAPR_HOME/conf
    [ $? -ne 0 ] && exitFailure "Could not save maprserverticket to ${MAPR_HOME}/conf"

    scp -i /home/${MAPR_USER}/.ssh/installer_key -r -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ${MAPR_USER}@${SEC_MASTER}:$MAPR_HOME/conf/ssl_keystore $HOME
    chown -R ${MAPR_USER}:${MAPR_GROUP} $HOME/ssl_keystore
    ${SUDO:-} mv $HOME/ssl_keystore $MAPR_HOME/conf
    [ $? -ne 0 ] && exitFailure "Could not save ssh_keystore to ${MAPR_HOME}/conf"

    scp -i /home/${MAPR_USER}/.ssh/installer_key -r -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ${MAPR_USER}@${SEC_MASTER}:$MAPR_HOME/conf/ssl_truststore $HOME
    chown -R ${MAPR_USER}:${MAPR_GROUP} $HOME/ssl_truststore
    ${SUDO:-} mv $HOME/ssl_truststore $MAPR_HOME/conf
    [ $? -ne 0 ] && exitFailure "Could not save ssh_truststore to ${MAPR_HOME}/conf"

    # For both CLDB and ZK nodes, we need the cldb.key
    if [ -f $MAPR_HOME/roles/cldb  -o  -f $MAPR_HOME/roles/zookeeper ] ; then
        scp -i /home/${MAPR_USER}/.ssh/installer_key -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ${MAPR_USER}@${SEC_MASTER}:$MAPR_HOME/conf/cldb.key $HOME
        chown -R ${MAPR_USER}:${MAPR_GROUP} $HOME/cldb.key
        ${SUDO:-} mv $HOME/cldb.key $MAPR_HOME/conf
        [ $? -ne 0 ] && exitFailure "Could not save cldb.key to ${MAPR_HOME}/conf"
    fi

    [ ${LOG_TIMING:-0} -ne 0 ] && \
        echo "  Exiting retrieve_mapr_security_credentials  at "`date +"%H:%M:%S"`

    return 0
}



#	Ansbile Integration: if $1 is passed in, we assume it is the 
#	ansible argument passing logic (a dump of key-value pairs).  
#	This sed expression parses it out.
#		No, I'm not that good a sed programmer; found this example
#		on the Ansible web site.	DBT  30-Oct-2013

if [ -n "${1}"  -a  -f "${1}" ] ; then
    eval $(sed -e "s/\s?\([^=]+\)\s?=\s?\(\x22\([^\x22]+\)\x22|\x27\([^\x27]+\)\x27|\(\S+\)\)\s?/\1='\2'/p" $1)
    ANSIBLE_PARENT=1
fi

MAPR_HOME=${MAPR_HOME:-/opt/mapr}
MAPR_USER=${MAPR_USER:-mapr}
MAPR_GROUP=${MAPR_USER:-mapr}

echo "-----------" >> $LOG
echo "SEC_MASTER=${SEC_MASTER:-<not_set>}" >> $LOG

# We need a few more details to handle the configuration,
# based on the version.
ver=0.0.0
[ -f $MAPR_HOME/MapRBuildVersion ] && ver=`cat $MAPR_HOME/MapRBuildVersion` 
mapr_major_version=${ver%%.*}
ver=${ver#*.}
mapr_minor_version=${ver%%.*}
mapr_version="${mapr_major_version}${mapr_minor_version}"

if [ $mapr_version -le 30 ] ; then
    exitSuccess "Nothing to do"
    exit 0
else 
    if [ -z "${SEC_MASTER}" ] ; then
        exitFailure "Module needs MapR Security Master specified"
        exit 0
    fi
fi

retrieve_mapr_security_credentials
if [ $? -eq 0 ] ; then
    exitSuccess "OK"
else
    RV=$?
    echo "retrieve_mapr_security_credentials failed with error code $RV" >> $LOG
    exitFailure "retrieve_mapr_security_credentials failed with error $RV"
fi

exit 0

