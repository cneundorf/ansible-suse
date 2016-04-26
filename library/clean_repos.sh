#!/bin/bash
#
# (c) 2016 MapR Technologies, Inc. All Rights Reserved
#
#
# @file: clean_repos.sh

function exitSuccess() {
    if [ -n ${ANSIBLE_PARENT} ]; then
        echo "{\"changed\":true, \"msg\":\"$1\"}"
        exit 0
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

if [ -n "${1}"  -a  -f "${1}" ] ; then
    eval $(sed -e "s/\s?\([^=]+\)\s?=\s?\(\x22\([^\x22]+\)\x22|\x27\([^\x27]+\)\x27|\(\S+\)\)\s?/\1='\2'/p" $1)
    ANSIBLE_PARENT=1

    [ -z "${OS_FAMILY}" ] && exitFailure "OS_FAMILY is not set"

    if [ "${OS_FAMILY:-}" = "Debian" ]; then
        for repoFile in `grep -E 'package.mapr.com|archive.mapr.com|package.qa.lab|apt.qa.lab' /etc/apt/sources.list.d/*.list -l | grep -v mapr.installer`; do
            mv $repoFile $repoFile.disabled
            if [ $? -ne 0 ]; then
                repoName=$(basename $repoFile)
                exitFailure "Unable to disable repository file $repoName"
            fi
        done
    fi

    if [ "${OS_FAMILY:-}" = "RedHat" ]; then
        for repoFile in `grep -E 'package.mapr.com|archive.mapr.com|package.qa.lab|yum.qa.lab' /etc/yum.repos.d/*.repo -l | grep -v mapr.installer`; do
            mv $repoFile $repoFile.disabled
            if [ $? -ne 0 ]; then
                repoName=$(basename $repoFile)
                exitFailure "Unable to disable repository file $repoName"
            fi
        done
    fi

    if [ "${OS_FAMILY:-}" = "Suse" ]; then
        for repoFile in `grep -E 'package.mapr.com|archive.mapr.com|package.qa.lab|yum.qa.lab' /etc/zypp/repos.d/*.repo -l | grep -v mapr.installer`; do
            mv $repoFile $repoFile.disabled
            if [ $? -ne 0 ]; then
                repoName=$(basename $repoFile)
                exitFailure "Unable to disable repository file $repoName"
            fi
        done
    fi

    exitSuccess "disabled existing repo files if any"
fi
