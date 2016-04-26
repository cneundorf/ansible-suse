#!/bin/bash
#
# (c) 2014 MapR Technologies, Inc. All Rights Reserved
#
#
# @file: openjdk_check.sh

JAVA_MIN=
JAVA_MAJ=

function exitSuccess() {
    if [ -n ${ANSIBLE_PARENT} ]; then
        echo "{\"changed\":true, \"version\":\"${2}.${3}\", \"jre_only\":\"${4}\", \"msg\":\"$1\"}"
        exit 0
    else
        echo "$1"
    fi
    exit 0
}

function exitFailure() {
    if [ -n ${ANSIBLE_PARENT} ]; then
        echo "{\"changed\":false, \"version\":\"${2}.${3}\", \"jre_only\":\"0\", \"msg\":\"$1\"}"
        exit 0
    else
        echo "$1"
        exit 1
    fi
}

function checkJavaVersion() {
    export JDK_REQUIRED=1
    export JDK_QUIET_CHECK=1

    # see if we have a compatible JDK installed
    . "${JAVA_ENV_CHECK_SCRIPT}"
    if [ -z "${JAVA_HOME}" ] ; then
        # we didn't find the complete jdk - look for jre
        export JDK_REQUIRED=0
        . "${JAVA_ENV_CHECK_SCRIPT}"
        if [ -n "${JAVA_HOME}" ] ; then
            JRE_ONLY=1
        fi
    fi

    RV=1
    if [ -n "${JAVA_HOME}" ] ; then
        j_maj=$($JAVA_HOME/bin/java -version 2>&1 | head -n1 | cut -d '.' -f 1)
        j_maj=${j_maj/java version \"} # remove unwanted text
        j_maj=${j_maj/openjdk version \"} # openjdk 8 has a different string
        j_min=$($JAVA_HOME/bin/java -version 2>&1 | head -n1 | cut -d '.' -f 2)
        if [ ${j_maj} -ge "${JAVA_MAJ}" ] ; then
            if [ ${j_maj} -eq "${JAVA_MAJ}" -a ${j_min} -lt ${JAVA_MIN} ] ; then
                RV=1 # minor version to low
            else
                if [ ${JRE_ONLY} -eq 1 ] ; then
                    RV=2
                else
                    RV=0
                fi
            fi
        else
            RV=1 # major version to low
        fi
    fi

    return ${RV}
}

j_maj=0
j_min=0
JRE_ONLY=0
if [ -n "${1}"  -a  -f "${1}" ] ; then
    eval $(sed -e "s/\s?\([^=]+\)\s?=\s?\(\x22\([^\x22]+\)\x22|\x27\([^\x27]+\)\x27|\(\S+\)\)\s?/\1='\2'/p" $1)
    ANSIBLE_PARENT=1

    [ -z "${MIN_JAVA_VERSION}" ] && exitFailure "MIN_JAVA_VERSION not set"
    [ -z "${JAVA_ENV_CHECK_SCRIPT}" ] && exitFailure "JAVA_ENV_CHECK_SCRIPT not set"
    [ ! -e "${JAVA_ENV_CHECK_SCRIPT}" ] && exitFailure "JAVA_ENV_CHECK_SCRIPT does not exist"

    IFS='.' read -a JAVA_VERSION <<< "${MIN_JAVA_VERSION}"

    if [ "${#JAVA_VERSION}" -eq 2 ]; then
        exitFailure "Invalid JAVA_VERSION"
    fi

    JAVA_MAJ=${JAVA_VERSION[0]}
    JAVA_MIN=${JAVA_VERSION[1]}

    checkJavaVersion
    RV=$?
    if [ ${RV} -eq 1 ]; then
        exitFailure "requires a minimum java version of ${MIN_JAVA_VERSION}" ${j_maj} ${j_min} ${JRE_ONLY}
    elif [ ${RV} -eq 2 ] ; then
        exitSuccess "minimum java version requirement met - but jre only - upgrade" ${j_maj} ${j_min} ${JRE_ONLY}
    else
        exitSuccess "minimum java version requirement met " ${j_maj} ${j_min} ${JRE_ONLY}
    fi
fi
