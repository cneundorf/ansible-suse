#!/bin/sh
#
# (c) 2016 MapR Technologies, Inc. All Rights Reserved.
#
#
#
########################################################

MAPR_ROLES=/opt/mapr/roles
TMP_ROLES=/tmp/installer.roles

[ -n "$1" -a -f "$1" ] && eval $(sed -e "s/\s?\([^=]+\)\s?=\s?\(\x22\([^\x22]+\)\x22|\x27\([^\x27]+\)\x27|\(\S+\)\)\s?/\1='\2'/p" $1)

if [ "$enable" = false ]; then
    mkdir -p $TMP_ROLES
    roles=$(cd $MAPR_ROLES 2> /dev/null && ls -1 $roles 2> /dev/null | egrep -v '^cldb|^fileserver|^hbinternal|^historyserver|^jobtracker|^metrics|^nfs|^nodemanager|^resourcemanager|^tasktracker|^webserver|^zookeeper')
    if [ -n "$roles" ]; then
        (cd $MAPR_ROLES && mv $roles $TMP_ROLES)
        echo "{\"changed\": true, \"msg\": \"$(echo $roles | tr '\n' ' ')roles disabled\"}"
    else
        echo "{\"changed\": false, \"msg\": \"no roles disabled\"}"
    fi
elif [ "$enable" = true ]; then
    roles=$(cd $TMP_ROLES 2> /dev/null && ls -1 $roles 2> /dev/null)
    if [ -n "$roles" ]; then
        (cd $TMP_ROLES && mv $roles $MAPR_ROLES)
        echo "{\"changed\": true, \"msg\": \"$(echo $roles | tr '\n' ' ')roles enabled\"}"
    else
        echo "{\"changed\": false, \"msg\": \"no roles enabled\"}"
    fi
else
    echo "usage: $1 enable=true|false roles=\"role1 role2...\""
    exit 1
fi
true
