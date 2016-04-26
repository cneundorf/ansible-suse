#!/bin/bash
#
# (c) 2016 MapR Technologies, Inc. All Rights Reserved.
#
# Deployer
#
# @file: check_patch_version.sh

LOG=/tmp/check_patch_version.sh

if [ -n "${1}" -a -f "${1}" ]; then
    eval $(sed -e "s/\s?\([^=]+\)\s?=\s?\(\x22\([^\x22]+\)\x22|\x27\([^\x27]+\)\x27|\(\S+\)\)\s?/\1='\2'/p" $1)

    [ -z "${DISTRO}" ] && exit 1
    [ -z "${PATCH_FILE}" ] && exit 1

    QUERY_CMD=""

    if [ "${DISTRO}" = "RedHat" ]; then
        QUERY_CMD="rpm -q mapr-patch"
        EXT=".rpm"
    elif [ "${DISTRO}" = "Debian" ]; then
        QUERY_CMD="dpkg -s mapr-patch | grep '^Version:'"
        EXT=".rpm"
    else
        echo "Unsupported Distro: ${DISTRO}" >> $LOG
        echo "{\"failed\":true, \"msg\":\"Unsupported Distro: ${DISTRO}\"}"
        exit 1
    fi

    InstalledVersion=`${QUERY_CMD} | grep -Eo 'GA-([0-9])+' | sed 's/GA-//g'`
    if [ $? -eq 0 ]; then
        echo "Installed Version: $InstalledVersion" >> $LOG
        QueryVersion=`basename ${PATCH_FILE} ${EXT} | grep -Eo 'GA-([0-9])+' | sed 's/GA-//g'`
        if [ $? -eq 0 ]; then
            echo "Query Version: $QueryVersion" >> $LOG
            echo "{\"changed\":true, \"InstalledVersion\":\"${InstalledVersion}\", \"QueryVersion\":\"${QueryVersion}\"}"
            exit 0
        fi
        echo "Failed QueryVersion: basename -s ${EXT} ${PATCH_FILE} | grep -Eo 'GA-([0-9])+' | sed 's/GA-//g'" >> $LOG
        echo "{\"failed\":true, \"msg\":\"An error occurred. Please look at log file $LOG on the node with errors fore more details\"}"
        exit 1
    fi

    echo "Failed InstallVersion: ${QUERY_CMD} | grep -Eo 'GA-([0-9])+' | sed 's/GA-//g'" >> $LOG
    echo "{\"failed\":true, \"msg\":\"An error occurred. Please look at log file $LOG on the node with errors fore more details\"}"
    exit 1
fi
