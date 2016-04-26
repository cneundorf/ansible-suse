#!/bin/bash
#
# (c) 2016 MapR Technologies, Inc. All Rights Reserved.
#
#
#
# @file: configure.sh
#########################################################
LOG=/tmp/tt.log

function exitSuccess() {
    if [ -n ${ANSIBLE_PARENT} ]; then
        echo "{\"changed\":true, \"msg\":\"$1\"}"
    else
        echo "$1"
    fi
    exit 0
}

function exitFailure() {
    if [ -n ${ANSIBLE_PARENT} ]; then
        echo "{\"failed\":true, \"msg\":\"$1\"}"
        exit 0
    else
        echo "$1"
        exit 1
    fi
}

# Ansbile Integration: if $1 is passed in, we assume it is the 
# ansible argument passing logic (a dump of key-value pairs).  
# This sed expression parses it out.
#   No, I'm not that good a sed programmer; found this example
#   on the Ansible web site.  DBT  30-Oct-2013

if [ -n "${1}"  -a  -f "${1}" ] ; then
    eval $(sed -e "s/\s?\([^=]+\)\s?=\s?\(\x22\([^\x22]+\)\x22|\x27\([^\x27]+\)\x27|\(\S+\)\)\s?/\1='\2'/p" $1)
    ANSIBLE_PARENT=1

    [ -z "${MAPR_HOME}" ] && exitFailure "MAPR_HOME not set"

    # Only run configure.sh -R on server roles.
    if which maprcli &> /dev/null ; then
        ${MAPR_HOME}/server/configure.sh -R
        if [ $? -eq 0 ]; then
            exitSuccess "OK"
        else
            cfgErr=$?
            echo "configure.sh failed with error code $cfgErr" >> $LOG
            exitFailure "configure.sh failed with error code $cfgErr"
        fi
    else
        exitSuccess "OK"
    fi
fi

exit 0

