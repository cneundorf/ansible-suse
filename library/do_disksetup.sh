#!/bin/bash
#
# (c) 2013 MapR Technologies, Inc. All Rights Reserved.
#
# Deployer
#
# @file:    do_disksetup.sh
##########################################################


# Very simple wrapper script around disksetup.

# Helper functions for exiting properly for Ansible
#	exitSucess <msg>   # eg ansible_exit "OK"
#	ansible_fail <msg>   # eg ansible_exit "Unable to create <foo>"
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
STRIPE_WIDTH=${STRIPE_WIDTH:-0}
FORCE_FORMAT=${FORCE_FORMAT:-False}

# Do nothing if fileserver package does not exist
if [ ! -f ${MAPR_HOME}/roles/fileserver ] ; then
    echo "{\"changed\":false, \"msg\":\"Nothing to do\"}"
    exit 0
fi

if [ -n "${DISKFILE}" ] ; then
    if [ ! -r "${DISKFILE}" ] ; then
        exitFailure "MapR DISKFILE ($DISKFILE) not found"
    fi

    DISKSETUP=${MAPR_HOME}/server/disksetup
    if [ ! -x "${DISKSETUP}" ] ; then
        exitFailure "MapR disksetup utility ($DISKSETUP) not found"
    fi

    ARGS=""

    if [ "${STRIPE_WIDTH}" -eq "0" ]; then
        ARGS="-M"
    else
        ARGS="${ARGS} -W ${STRIPE_WIDTH}"
    fi

    if [ "${FORCE_FORMAT}" = "True" ]; then
        ARGS="${ARGS} -F"
    fi

    ${DISKSETUP} ${ARGS} ${DISKFILE}

    if [ $? -eq 0 ] ; then
        exitSuccess "Local disks formatted for MapR-FS"
    else
        msg="$DISKSETUP failed with error code $?"
        rm -f ${MAPR_HOME}/conf/disktab
        exitFailure "$msg"
    fi
else
    exitFailure "Module needs DISKFILE= argument"
fi

exit 0

