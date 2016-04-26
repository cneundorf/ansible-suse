#!/bin/bash
#
# (c) 2016 MapR Technologies, Inc. All Rights Reserved.
#
# Deployer
#
# @file:    maprgroup.sh
#
#	Sample script file for use with Ansible playbooks.
#
#	Ansible syntax will be
#		action: <this_script>.sh ARG1="MyArg1" ARG2="MyArg2"
##########################################################

LOG=/tmp/maprgroup.log

#	Ansbile Integration: if $1 is passed in, we assume it is the
#	ansible argument passing logic (a dump of key-value pairs).
#	This sed expression parses it out.
#		No, I'm not that good a sed programmer; found this example
#		on the Ansible web site.	DBT  30-Oct-2013

function log_changed() {
    log "{\"changed\": $1, \"msg\":\"$2\"}"
}

function log_failed() {
    log "{\"failed\": true, \"msg\":\"$1\"}"
}


function log() {
    if [ $# -eq 1 ]; then
        echo $1 | tee -a ${LOG}
    fi
}

if [ -n "${1}" -a -f "${1}" ]; then
    eval $(sed -e "s/\s?\([^=]+\)\s?=\s?\(\x22\([^\x22]+\)\x22|\x27\([^\x27]+\)\x27|\(\S+\)\)\s?/\1='\2'/p" $1)

    [ -z "${MAPR_GID}" ] && echo "MAPR_USER required" && exit 1
    [ -z "${MAPR_GROUP}" ] && echo "MAPR_GROUP required" && exit 1

    CMD="groupadd"

    grep -i "^${MAPR_GROUP}:" /etc/group > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        # User does not exist
        log "${CMD} -g ${MAPR_GID} ${MAPR_GROUP}"
        ${CMD} -g ${MAPR_GID} ${MAPR_GROUP}
        if [ $? -eq 0 ]; then
            log_changed "true" "${MAPR_GROUP} group created"
        else
            log_failed "failed to create ${MAPR_GROUP} group (error $?)"
        fi
    else
        # The group exists.
        log_changed "false" "Group ${MAPR_GROUP} already exists"
    fi
else
    log_failed "Module needs maprgroup arguments."
fi

exit 0
