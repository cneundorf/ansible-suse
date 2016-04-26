#!/bin/bash
#
# (c) 2016 MapR Technologies, Inc. All Rights Reserved.
#
# Deployer
#
# @file:    find_disks.sh
##########################################################


# Some of this logic was developed for other provisioning
# tools.   We'll use a default log for now ... better logging later.

LOG=/tmp/find_disks.log

function remove_from_fstab() {
    mnt=${1}
    [ -z "${mnt}" ] && return

    FSTAB=/etc/fstab
    [ ! -w $FSTAB ] && return

    # BE VERY CAREFUL with sedOpt here ... tabs and spaces are included
    sedOpt="/[ 	]"`echo "$mnt" | sed -e 's/\//\\\\\//g'`"[ 	]/d"
    sed -i.mapr_save "$sedOpt" $FSTAB
    if [ $? -ne 0 ] ; then
        echo "[ERROR]: failed to remove $mnt from $FSTAB"
    fi
}

function unmount_unused() {
    [ -z "${1}" ] && return

    echo "Unmounting filesystems ($1)" >> $LOG

    fsToUnmount=${1:-}

    for fs in `echo ${fsToUnmount//,/ }`
    do
        echo -n "$fs in use by " >> $LOG
        fuser $fs >> $LOG 2> /dev/null
        if [ $? -ne 0 ] ; then
            echo "<no_one>" >> $LOG
            umount $fs 2> /dev/null
            remove_from_fstab $fs
        else
            echo "" >> $LOG
            pids=`grep "^${fs} in use by " $LOG | cut -d' ' -f5-`
            for pid in $pids
            do
                ps --no-headers -p $pid >> $LOG
            done
        fi
    done
}

# Use fdisk to check for available disk spindles.
#	Advantages: fdisk seems to be on all Linux Distros
#	Disadvantages: fdisk can only be run as root.
find_mapr_disks() {
    disks=""
    for d in `fdisk -l 2>/dev/null | grep -e "^Disk .* bytes$" | awk '{print $2}' `
    do
        dev=${d%:}

        cfdisk -P s $dev &> /dev/null
        [ $? -eq 0 ] && continue

        mount | grep -q -w -e $dev -e ${dev}1 -e ${dev}2
        [ $? -eq 0 ] && continue

        swapon -s | grep -q -w $dev
        [ $? -eq 0 ] && continue

        if which readlink &> /dev/null ; then
            realdev=`readlink -f $dev`
            swapon -s | grep -q -w $realdev
            [ $? -eq 0 ] && continue
        fi

        if which pvdisplay &> /dev/null ; then
            pvdisplay $dev &> /dev/null
            [ $? -eq 0 ] && continue
        fi

        disks="$disks $dev"
    done

    # Strip off leading space
    MAPR_DISKS="${disks# }"
    export MAPR_DISKS

    echo "MAPR_DISKS=${MAPR_DISKS// /,}"
}

# For Amazon instances, we can ditch the "/mnt" and /media/ephemeral
# directories if they are not in use.  Do this before find_mapr_disks
# operation.
unmount_unused /mnt

if [ -d /media/ephemeral0 ] ; then
    for d in /media/ephemeral? ; do
        unmount_unused $d
    done
fi

echo "Args: $@" >> $LOG
find_mapr_disks


#	Ansbile Integration: if $1 is passed in, we assume it is the
#	ansible argument passing logic (a dump of key-value pairs).
#	This sed expression parses it out.
#		No, I'm not that good a sed programmer; found this example
#		on the Ansible web site.	DBT  30-Oct-2013

if [ -n "${1}"  -a  -f "${1}" ] ; then
    eval $(sed -e "s/\s?\([^=]+\)\s?=\s?\(\x22\([^\x22]+\)\x22|\x27\([^\x27]+\)\x27|\(\S+\)\)\s?/\1='\2'/p" $1)

    msg="OK"
    if [ -n "${DISKFILE}" ] ; then
        for d in $MAPR_DISKS ; do
            echo $d >> $DISKFILE
        done
        msg="MapR DISKFILE ${DISKFILE} created with ${MAPR_DISKS// /,}"
    fi
    echo "{\"changed\":true, \"msg\":\"${msg}\"}"
else
    echo '{"failed":true, "msg"="Module needs DISKFILE= argument"}'
fi

exit 0
