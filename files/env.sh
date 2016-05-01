#!/bin/bash
# Copyright (c) 2009 & onwards. MapR Tech, Inc., All rights reserved
# Please set all environment variable you want to be used during MapR cluster
# runtime here.
# namely MAPR_HOME, JAVA_HOME, MAPR_SUBNETS

#set JAVA_HOME to override default search
export JAVA_HOME=/opt/jdk1.8.0_92
#export MAPR_SUBNETS=
#export MAPR_HOME=
#export MAPR_ULIMIT_U=
#export MAPR_ULIMIT_N=
#export MAPR_SYSCTL_SOMAXCONN=

# Need special handling for OSX
ISDARWIN=0
p_readlink() {
    perl -MCwd -e 'print Cwd::abs_path shift' $1
}

if [ $(uname -s) = 'Darwin' ]; then
    ISDARWIN=1
    READLINK="p_readlink"
else
    READLINK="readlink -f"
fi

# We use this flag to force checks for full JDK
JDK_QUIET_CHECK=${JDK_QUIET_CHECK:-0}
JDK_REQUIRED=${JDK_REQUIRED:-0}

# WARNING: The code from here to the next tag is included in mapr-setup.sh.
#          any changes should be applied there too
check_java_home() {
    local found=0
    if [ -n "$JAVA_HOME" ]; then
        if [ ${JDK_REQUIRED} -eq 1 ]; then
            if [ -e "$JAVA_HOME"/bin/javac -a -e "$JAVA_HOME"/bin/java ]; then
                found=1
            fi
        elif [ -e "$JAVA_HOME"/bin/java ]; then
            found=1
        fi
        if [ $found -eq 1 ]; then
            if java_version=$($JAVA_HOME/bin/java -version 2>&1); then
                java_version=$(echo "$java_version" | head -n1 | cut -d '.' -f 2)
                [ -z "$java_version" ] || [ $java_version -le 6 ] && unset JAVA_HOME
            else
                unset JAVA_HOME
            fi
        else
            unset JAVA_HOME
        fi
    fi
}

# Handle special case of bogus setting in some virtual machines
[ "${JAVA_HOME:-}" = "/usr" ] && JAVA_HOME=""

# Look for installed JDK
if [ -z "$JAVA_HOME" ]; then
    sys_java="/usr/bin/java"
    if [ -e $sys_java ]; then
        jcmd=$($READLINK $sys_java)
        if [ $JDK_REQUIRED -eq 1 ]; then
            if [ -x ${jcmd%/jre/bin/java}/bin/javac ]; then
                JAVA_HOME=${jcmd%/jre/bin/java}
            elif [ -x ${jcmd%/java}/javac ]; then
                JAVA_HOME=${jcmd%/bin/java}
            fi
        else
            if [ -x ${jcmd} ]; then
                JAVA_HOME=${jcmd%/bin/java}
            fi
        fi
        # overwrite java home to the correct one on OSX
        [ $ISDARWIN -eq 1 -a -n "$JAVA_HOME" ] && JAVA_HOME=$(${jcmd}_home)
        [ -n "$JAVA_HOME" ] && export JAVA_HOME
    fi
fi

check_java_home

# MARKER - DO NOT DELETE THIS LINE
# attempt to find java if JAVA_HOME not set
if [ -z "$JAVA_HOME" ]; then
    for candidate in \
        /Library/Java/Home \
        /Library/Java/JavaVirtualMachines/jdk1.8.*/Contents/Home \
        /Library/Java/JavaVirtualMachines/jdk1.7.*/Contents/Home \
        /usr/java/default \
        /usr/lib/jvm/default-java \
        /usr/lib*/jvm/java-8-openjdk* \
        /usr/lib*/jvm/java-8-oracle* \
        /usr/lib*/jvm/java-8-sun* \
        /usr/lib*/jvm/java-1.8.* \
        /usr/lib*/jvm/java-7-openjdk* \
        /usr/lib*/jvm/java-7-oracle* \
        /usr/lib*/jvm/java-7-sun* \
        /usr/lib*/jvm/java-1.7.* ; do
        if [ -e $candidate/bin/java ]; then
            export JAVA_HOME=$candidate
            check_java_home
            if [ -n "$JAVA_HOME" ]; then
                break
            fi
        fi
    done
    # if we didn't set it
    if [ -z "$JAVA_HOME" -a $JDK_QUIET_CHECK -ne 1 ]; then
        cat 1>&2 <<EOF
+======================================================================+
|      Error: JAVA_HOME is not set and Java could not be found         |
+----------------------------------------------------------------------+
| MapR requires Java 1.7 or later.                                     |
| NOTE: This script will find Oracle or Open JDK Java whether you      |
|       install using the binary or the RPM based installer.           |
+======================================================================+
EOF
        exit 1
    fi
fi

# export JAVA_HOME to PATH
export PATH=$JAVA_HOME/bin:$PATH

# WARNING: The code above is also in mapr-setup.sh

# For Kerberos SSO support
# kerberos and ssl conf needed for kerberos sso
MAPR_HOME=${MAPR_HOME:=/opt/mapr}
MAPR_LOGIN_CONF=$MAPR_HOME/conf/mapr.login.conf
MAPR_CLUSTERS_CONF=$MAPR_HOME/conf/mapr-clusters.conf
SSL_TRUST_STORE=$MAPR_HOME/conf/ssl_truststore

MAPR_SECURITY_STATUS=false
if [ -r $MAPR_CLUSTERS_CONF ]; then
    MAPR_SECURITY_STATUS=$(head -n 1 $MAPR_CLUSTERS_CONF | grep secure= | sed 's/^.*secure=//' | sed 's/ .*$//')
fi

# uncomment the following line to debug client kerberos issues
#MAPR_KERBEROS_DEBUG="-Dsun.security.krb5.debug=true -Dsun.security.spnego.debug=true -Djavax.net.debug=all"
MAPR_KERBEROS_DEBUG="-Dsun.security.krb5.debug=true -Dsun.security.spnego.debug=true -Dorg.apache.hadoop.security.debug=all -Djavax.net.debug=all -Djavax.net.debug=ssl -Djavax.net.debug=ssl:record -Djavax.net.debug=ssl:handshake"

# security configuration for individual components
MAPR_JAAS_CONFIG_OPTS="-Djava.security.auth.login.config=${MAPR_LOGIN_CONF} ${MAPR_KERBEROS_DEBUG}"

if [ "$MAPR_SECURITY_STATUS" = "true" ]; then
    MAPR_ZOOKEEPER_OPTS="-Dzookeeper.saslprovider=com.mapr.security.maprsasl.MaprSaslProvider"
    MAPR_ECOSYSTEM_LOGIN_OPTS="-Dhadoop.login=hybrid"
    MAPR_ECOSYSTEM_SERVER_LOGIN_OPTS="-Dhadoop.login=hybrid_keytab"
    MAPR_HIVE_SERVER_LOGIN_OPTS="-Dhadoop.login=maprsasl_keytab"
    MAPR_HIVE_LOGIN_OPTS="-Dhadoop.login=maprsasl"
    MAPR_SSL_OPTS="-Djavax.net.ssl.trustStore=${SSL_TRUST_STORE}"
else
    MAPR_ZOOKEEPER_OPTS="-Dzookeeper.sasl.clientconfig=Client_simple -Dzookeeper.saslprovider=com.mapr.security.simplesasl.SimpleSaslProvider"
    MAPR_ECOSYSTEM_LOGIN_OPTS="-Dhadoop.login=simple"
    MAPR_ECOSYSTEM_SERVER_LOGIN_OPTS="-Dhadoop.login=simple"
    MAPR_HIVE_SERVER_LOGIN_OPTS="-Dhadoop.login=simple"
    MAPR_HIVE_LOGIN_OPTS="-Dhadoop.login=simple"
    ZOOKEEPER_SERVER_OPTS="-Dzookeeper.sasl.serverconfig=Server_simple"
fi

# used by various servers and clients
HYBRID_LOGIN_OPTS="-Dhadoop.login=hybrid ${MAPR_JAAS_CONFIG_OPTS} ${MAPR_ZOOKEEPER_OPTS}"
# KERBEROS_LOGIN_OPTS is used by flume-ng script. If you change this variable be sure to
# make corresponding changes in flume-ng script as well.
KERBEROS_LOGIN_OPTS="-Dhadoop.login=kerberos ${MAPR_JAAS_CONFIG_OPTS} ${MAPR_ZOOKEEPER_OPTS}"
SIMPLE_LOGIN_OPTS="-Dhadoop.login=simple ${MAPR_JAAS_CONFIG_OPTS} ${MAPR_ZOOKEEPER_OPTS}"
MAPR_LOGIN_OPTS="-Dhadoop.login=maprsasl -Dhttps.protocols=TLSv1.2 ${MAPR_JAAS_CONFIG_OPTS} ${MAPR_ZOOKEEPER_OPTS}"

MAPR_AUTH_CLIENT_OPTS="${MAPR_LOGIN_OPTS} ${MAPR_SSL_OPTS}"

export MAPR_ECOSYSTEM_LOGIN_OPTS="${MAPR_ECOSYSTEM_LOGIN_OPTS} ${MAPR_JAAS_CONFIG_OPTS} ${MAPR_ZOOKEEPER_OPTS} ${MAPR_SSL_OPTS} -Dmapr.library.flatclass"
export MAPR_ECOSYSTEM_SERVER_LOGIN_OPTS="${MAPR_ECOSYSTEM_SERVER_LOGIN_OPTS} ${MAPR_JAAS_CONFIG_OPTS} ${MAPR_ZOOKEEPER_OPTS} ${MAPR_SSL_OPTS} -Dmapr.library.flatclass"
export MAPR_HIVE_SERVER_LOGIN_OPTS="${MAPR_HIVE_SERVER_LOGIN_OPTS} ${MAPR_JAAS_CONFIG_OPTS} ${MAPR_ZOOKEEPER_OPTS} ${MAPR_SSL_OPTS} -Dmapr.library.flatclass"
export MAPR_HIVE_LOGIN_OPTS="${MAPR_HIVE_LOGIN_OPTS} ${MAPR_JAAS_CONFIG_OPTS} ${MAPR_ZOOKEEPER_OPTS} ${MAPR_SSL_OPTS} -Dmapr.library.flatclass"

# ensure we can properly find the PAM shared libraries
libpamDir="/lib64"
if [ ! -d "/lib64" ]; then
    libpamDir="/lib"
fi
LIBPAM=$(find $libpamDir/libpam.so* 2>/dev/null | head -1)
if [ "$LIBPAM" != "" ]; then
    export LD_PRELOAD=$LIBPAM
fi

# Options relevant to HBase servers and clients
# HBase clients do not need to authenticate to Zookeeper even in a secured HBase cluster
# Replace ${SIMPLE_LOGIN_OPTS} in the following line with ${KERBEROS_LOGIN_OPTS} or
#  ${HYBRID_LOGIN_OPTS} for Kerberos secured HBase clusters running on secured MapR cluster
export MAPR_HBASE_CLIENT_OPTS="${SIMPLE_LOGIN_OPTS} -Dzookeeper.sasl.client=false"
# Replace ${SIMPLE_LOGIN_OPTS} in the following line with ${KERBEROS_LOGIN_OPTS}
#  for Kerberos secured HBase clusters
export MAPR_HBASE_SERVER_OPTS="${SIMPLE_LOGIN_OPTS} ${MAPR_SSL_OPTS} -Dmapr.library.flatclass"

export HADOOP_TASKTRACKER_OPTS="${HADOOP_TASKTRACKER_OPTS} ${MAPR_LOGIN_OPTS}"
export HADOOP_JOBTRACKER_OPTS="${HADOOP_JOBTRACKER_OPTS} ${MAPR_LOGIN_OPTS}"

# Zookeeper server options
export ZOOKEEPER_SERVER_OPTS="${ZOOKEEPER_SERVER_OPTS} ${MAPR_JAAS_CONFIG_OPTS} ${MAPR_ZOOKEEPER_OPTS}"
