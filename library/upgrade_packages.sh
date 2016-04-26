#!/bin/bash
#
# (c) 2016 MapR Technologies, Inc. All Rights Reserved.
#
# Deployer
#
# 

LOG=/tmp/upgrade_packages.log

installed_packages=""
upgrade_packages=""
MAPR_PREFIX="mapr"
TIMEOUT_KILL="timeout --preserve-status -s KILL -k 60m"
DPKG_UPGRADE="dpkg --force-all -i"
APT_GET="apt-get -qyf --force-yes "
RPM_UPGRADE="rpm --quiet --force --nosignature -U "
SUSE_UPGRADE="zypper --no-gpg-checks --non-interactive install -n"
newpackages=
corePackages=("$MAPR_PREFIX-cldb"
    "$MAPR_PREFIX-client"
    "$MAPR_PREFIX-core-internal"
    "$MAPR_PREFIX-core"
    "$MAPR_PREFIX-fileserver"
    "$MAPR_PREFIX-hadoop-core"
    "$MAPR_PREFIX-historyserver"
    "$MAPR_PREFIX-jobtracker"
    "$MAPR_PREFIX-mapreduce1"
    "$MAPR_PREFIX-mapreduce2"
    "$MAPR_PREFIX-metrics"
    "$MAPR_PREFIX-nfs"
    "$MAPR_PREFIX-nodemanager"
    "$MAPR_PREFIX-resourcemanager"
    "$MAPR_PREFIX-tasktracker"
    "$MAPR_PREFIX-webserver"
    "$MAPR_PREFIX-zk-internal"
    "$MAPR_PREFIX-zookeeper"
)

function contains_elem() {
    local e
    for e in "${@:2}"; do [[ "$e" == "$1" ]] && return 0; done
    return 1
}

if [ -n "${1}" -a -f "${1}" ]; then
    eval $(sed -e "s/\s?\([^=]+\)\s?=\s?\(\x22\([^\x22]+\)\x22|\x27\([^\x27]+\)\x27|\(\S+\)\)\s?/\1='\2'/p" $1)

    [ -z "${DISTRO}" ] && exit 1
    [ -z "${PKG_DIR}" ] && exit 1

    [ ! -d "${PKG_DIR}" ] && exit 1

    if [ "${DISTRO}" = "Debian" ]; then
        installed_packages=`dpkg -l | grep "${MAPR_PREFIX}-" | grep -Ev "(upgrade|$MAPR_PREFIX-patch)" | grep "^ii " | awk '{print $2}' | sort -u`
        echo "Installed Packages: $installed_packages" >> $LOG
        #To preserve the order of package upgrades we select corePackages agains installed pacakges
        for p in "${corePackages[@]}"; do
            #contains_elem "$p" "${installed_packages}"
            for ipkg in $installed_packages; do
                if [ "$p" = "$ipkg" ]; then
                    echo "Found package Core package $p in installed packages" >> $LOG
                    val=`find ${PKG_DIR} -iname ${p}_*.deb 2>/dev/null | grep -v nonstrip | head -1 | sed -e 's/\n//g'`
                    if [ $? -eq 0 -a "$val" != "" ]; then
                        echo "Found Location for $p as $val" >>$LOG
                        upgrade_packages="$upgrade_packages $val"
                    fi
                fi
            done
        done

        echo "Upgrade Packages: $upgrade_packages" >>$LOG
        echo "Simulating Upgrade" >> $LOG
        ${DPKG_UPGRADE} --dry-run $upgrade_packages >>$LOG 2>&1
        if [ $? -ne 0 ]; then
            echo "failed=True msg=\"Packages failed to upgrade during dry run\""
            exit 0
        fi
        echo "Performing Upgrade" >> $LOG
        ${DPKG_UPGRADE} $upgrade_packages >>$LOG 2>&1
        ${APT_GET} install >>$LOG 2>&1
        if [ $? -ne 0 ]; then
            echo "failed=True msg=\"Failed to upgrade some packages\""
            exit 0
        fi

        newpackages=`dpkg -l | grep "${MAPR_PREFIX}-" | grep -Ev "(upgrade|$MAPR_PREFIX-patch)" | grep "^ii" | awk '{print $2}' | sort -u`
    fi

    if [ "${DISTRO}" = "Redhat" ]; then
        installed_packages=`rpm -qa --queryformat '%{name}\n' | grep "$MAPR_PREFIX-" | grep -Ev "(upgrade|$MAPR_PREFIX-patch)" | sort -u`
        for p in "${corePackages[@]}"; do
            #contains_elem "$p" "${installed_packages[@]}"
            for ipkg in $installed_packages; do
                if [ "$p" == "$ipkg" ]; then
                    echo "Found Core package $p in installed packages: $installed_packages" >> $LOG
                    val=`find ${PKG_DIR} -name ${p}-*.rpm 2>/dev/null | grep -v nonstrip | head -1 | sed -e 's/\n//g'`
                    if [ $? -eq 0 -a "$val" != "" ]; then
                        echo "Found Location for $p as $val" >>$LOG
                        upgrade_packages="$upgrade_packages $val"
                    fi
                fi
            done
        done

        echo "Upgrade Packages: $upgrade_packages" >>$LOG
        echo "Simulating Upgrade" >>$LOG
        ${RPM_UPGRADE} --test $upgrade_packages >>$LOG 2>&1
        if [ $? -ne 0 ]; then
            echo "failed=True msg=\"Packages failed to upgrade during dry run\""
            exit 0
        fi
        echo "Performing Upgrade" >> $LOG
        ${RPM_UPGRADE} $upgrade_packages >>$LOG 2>&1
        if [ $? -ne 0 ]; then
            echo "failed=True msg=\"Failed to upgrade some packages\""
            exit 0
        fi

        newpackages=`rpm -qa --queryformat '%{name}\n' | grep "$MAPR_PREFIX-" | grep -Ev "(upgrade|$MAPR_PREFIX-patch)" | sort -u`
    fi

    if [ "${DISTRO}" = "Suse" ]; then
        installed_packages=`rpm -qa --queryformat '%{name}\n' | grep "$MAPR_PREFIX-" | grep -Ev "(upgrade|$MAPR_PREFIX-patch)" | sort -u`
        for p in "${corePackages[@]}"; do
            #contains_elem "$p" "${installed_packages[@]}"
            for ipkg in $installed_packages; do
                if [ "$p" == "$ipkg" ]; then
                    echo "Found Core package $p in installed packages: $installed_packages" >> $LOG
                    val=`find ${PKG_DIR} -name ${p}-*.rpm 2>/dev/null | grep -v nonstrip | head -1 | sed -e 's/\n//g'`
                    if [ $? -eq 0 -a "$val" != "" ]; then
                        echo "Found Location for $p as $val" >>$LOG
                        upgrade_packages="$upgrade_packages $val"
                    fi
                fi
            done
        done

        echo "Upgrade Packages: $upgrade_packages" >>$LOG
        echo "Performing Upgrade" >> $LOG
        ${SUSE_UPGRADE} $upgrade_packages >>$LOG 2>&1
        if [ $? -ne 0 ]; then
            echo "failed=True msg=\"Failed to upgrade some packages\""
            exit 0
        fi

        newpackages=`rpm -qa --queryformat '%{name}\n' | grep "$MAPR_PREFIX-" | grep -Ev "(upgrade|$MAPR_PREFIX-patch)" | sort -u`
    fi

    for p in $installed_packages; do
        if [ "`echo $newpackages | grep $p`" = "" ]; then
            echo "failed=True msg=\"Some packages did not install correctly\""
            exit 0
        fi
    done

    echo "changed=True msg=\"All packages updated successfully\""
    exit 0
fi

