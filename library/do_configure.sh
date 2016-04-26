#!/bin/bash
#
# (c) 2016 MapR Technologies, Inc. All Rights Reserved.
#
LOG=/tmp/do_configure.log

# parse args
if [ -n "${1}" -a -f "${1}" ] ; then
    eval $(sed -e "s/\s?\([^=]+\)\s?=\s?\(\x22\([^\x22]+\)\x22|\x27\([^\x27]+\)\x27|\(\S+\)\)\s?/\1='\2'/p" $1)

    [ -z "${MAPR_HOME}" ] && exit 1
    MAPR_USER=${MAPR_USER:-mapr}
    MAPR_GROUP=${MAPR_GROUP:-mapr}
    SECURITY=${SECURITY:-disabled}
    YARN=${YARN:-}
    LICENSE_MODULES=${LICENSE_MODULES:-DATABASE,HADOOP}
    LICENSE_TYPE=${LICENSE_TYPE:-M3}

    echo "-----------" >> $LOG
    echo "CLUSTERNAME=$CLUSTERNAME" >> $LOG
    echo "LICENSE=$LICENSE_TYPE:$LICENSE_MODULES" >> $LOG
    echo "CLDBNODES=$CLDBNODES" >> $LOG
    echo "ZKNODES=$ZKNODES" >> $LOG

    cldbnodes=`echo $CLDBNODES | tr -d "[]"`
    zknodes=`echo $ZKNODES | tr -d "[]"`
    rmnodes=`echo $CLDBNODES | tr -d "[]"`
    yrnnode=`echo $YARN_MASTER`

    # We need a few more details to handle configuration based on version
    ver=0.0.0
    [ -f $MAPR_HOME/MapRBuildVersion ] && ver=`cat $MAPR_HOME/MapRBuildVersion`
    mapr_major_version=${ver%%.*}
    ver=${ver#*.}
    mapr_minor_version=${ver%%.*}
    ver=${ver#*.}
    mapr_triple_version=${ver%%.*}
    mapr_version="${mapr_major_version}${mapr_minor_version}${mapr_triple_version}"

    mapr_autostart_arg="-f -no-autostart -on-prompt-cont y"
    mapr_metrics_arg=
    mapr_yarn_arg=
    verbose_flag="-v"

    if [ "${SECURITY:-}" = "master" ]; then
        mapr_sec_arg="-secure -genkeys"
    elif [ "${SECURITY:-}" = "enabled" ]; then
        mapr_sec_arg="-secure"
    else
        mapr_sec_arg="-unsecure"
    fi

    # If we cannot find maprcli, assume this is a client node
    if which maprcli &> /dev/null; then
        mapr_client_args=""
    else
        mapr_client_args="-c"
    fi

    mapr_db_arg=""
    # disable MapR-DB memory allocation if not licensed
    if [ -n "${LICENSE_MODULES##*DATABASE*}" -a -n "${LICENSE_MODULES##*STREAMS*}" ]; then
        mapr_db_arg="-noDB"
    fi

    if [ "${YARN:-}" = "True" ]; then
        mapr_yarn_arg=""
        if [ ! -z ${HISTORYSERVER_HOST} ]; then
            mapr_yarn_arg="-HS ${HISTORYSERVER_HOST}"
        fi
        if [ $mapr_version -eq 401 ]; then
            mapr_yarn_arg="-RM $rmnodes ${mapr_yarn_arg}"
        fi
    fi

    if [ -n "$METRICS_DATABASE_HOST" ]; then
        mapr_metrics_arg="-d $METRICS_DATABASE_HOST:${METRICS_DATABASE_PORT} -du $METRICS_DATABASE_USER -dp $METRICS_DATABASE_PASSWORD -ds $METRICS_DATABASE_NAME"
    fi

    # Configure.sh wants JAVA_HOME set in order to find
    # some system utilities. We'll use env.sh to get that set.
    . $MAPR_HOME/conf/env.sh

    if [ -n "$CLDBNODES" ]; then
        $MAPR_HOME/server/configure.sh -N $CLUSTERNAME -C $cldbnodes -Z $zknodes -u $MAPR_USER -g $MAPR_GROUP ${mapr_autostart_arg:-} ${mapr_sec_arg:-} ${mapr_db_arg:-} ${verbose_flag:-} ${mapr_client_args:-} ${mapr_yarn_arg:-} ${mapr_metrics_arg:-} 2>&1 >> $LOG
        ret=$?
    else
        $MAPR_HOME/server/configure.sh -R ${verbose_flag:-} ${mapr_yarn_arg:-} ${mapr_metrics_arg:-} 2>&1 >> $LOG
        ret=$?
        # hbase-* might have started before configure.sh sets pid dir
        # kill dangling processes that cannot be managed by Warden
        for pidfile in /tmp/hbase*.pid; do
            pid=$(cat $pidfile)
            echo "killing unmanaged service $(basename $pidfile .pid):$pid" >> $LOG
            (kill $pid && sleep 2 && kill -9 $pid && rm -f $pidfile) 2> /dev/null
        done

        if [ -n "$RESTART_ECO" ]; then
            [ -n "$METRICS_DATABASE_HOST" ] && /usr/bin/maprcli node services -name hoststats -action restart -nodes $(hostname)
            for role in $(ls -1 /opt/mapr/roles | egrep -v '^cldb|^fileserver|^hbinternal|^historyserver|^jobtracker|^metrics|^nfs|^nodemanager|^resourcemanager|^tasktracker|^webserver|^zookeeper'); do
                echo "restarting $role role" >> $LOG
                [ "$role" = "storm-nimbus" ] && role=nimbus
                [ "$role" = "storm-supervisor" ] && role=supervisor
                /usr/bin/maprcli node services -name $role -action restart -nodes $(hostname)
            done
        fi
    fi

    if [ $ret -eq 0 ]; then
        echo '{"changed":true, "msg":"OK"}'
    else
        cfgErr=$?
        echo "configure.sh failed with error code $cfgErr" >> $LOG
        echo "{\"failed\":true, \"msg\":\"configure.sh failed with error $cfgErr\"}"
    fi
else
    echo '{"failed":true, "msg":"module needs configure.sh arguments"}'
fi

exit 0

