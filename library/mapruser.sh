#!/bin/bash
#
# (c) 2016 MapR Technologies, Inc. All Rights Reserved.
##########################################################

LOG=/tmp/mapruser.log

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

    [ -z "${MAPR_USER}" ] && echo "MAPR_USER required" && exit 1
    [ -z "${MAPR_UID}" ] && echo "MAPR_UID required" && exit 1
    [ -z "${MAPR_GROUP}" ] && echo "MAPR_GROUP required" && exit 1
    [ -z "${MAPR_SHELL}" ] && echo "MAPR_SHELL required" && exit 1
    [ -z "${MAPR_PASSWORD}" ] && echo "MAPR_PASSWORD required" && exit 1

    CMD="useradd"

    id "${MAPR_USER}" > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        # User does not exist
        log "${CMD} -u ${MAPR_UID} -g ${MAPR_GROUP} -s ${MAPR_SHELL} -p ${MAPR_PASSWORD} -m ${MAPR_USER}"
        ${CMD} -u ${MAPR_UID} -g ${MAPR_GROUP} -s ${MAPR_SHELL} -p ${MAPR_PASSWORD} -m ${MAPR_USER}
        if [ $? -eq 0 ]; then
            log_changed "true" "${MAPR_USER} user created"
        else
            log_failed "failed to create ${MAPR_USER} user (error $?)"
        fi
    else
        # The user exists but home directory doesn't.
        MAPR_USER_HOME=$(getent passwd ${MAPR_USER} | cut -d: -f6)
        if [ ! -d "${MAPR_USER_HOME}" ]; then
            mkdir -p ${MAPR_USER_HOME}
            chown ${MAPR_USER}:${MAPR_GROUP} ${MAPR_USER_HOME}
            log_changed "true" "User ${MAPR_USER} home directory created"
        else
            log_changed "false" "User ${MAPR_USER} already exists"
        fi
    fi
    # attempt to add to shadow group to support PAM auth
    usermod -G $(stat -c '%G' /etc/shadow) ${MAPR_USER}
else
    log_failed "Module needs mapruser arguments."
fi

exit 0
