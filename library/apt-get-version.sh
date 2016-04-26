#!/bin/bash
#
# (c) 2016 MapR Technologies, Inc. All Rights Reserved.
#
# apt-get does not properly auto-install dependencies for non-latest packages
#
##########################################################

LOG=/tmp/apt-get-version.log

if [ -n "$1" -a -f "$1" ]; then
    eval $(sed -e "s/\s?\([^=]+\)\s?=\s?\(\x22\([^\x22]+\)\x22|\x27\([^\x27]+\)\x27|\(\S+\)\)\s?/\1='\2'/p" $1)
fi

PACKAGES="$PACKAGE_NAME=$PACKAGE_VERSION.*"
DEPENDS=$(apt-cache depends $PACKAGES | grep 'Depends: mapr-' | grep -v '|' | egrep -v 'mapr-client|mapr-core' | cut -d: -f2)

for depend in $DEPENDS; do
    PACKAGES="$PACKAGES $depend=$PACKAGE_VERSION.*"
done

echo "/usr/bin/apt-get --allow-unauthenticated -y install $PACKAGES" >> $LOG
if /usr/bin/apt-get --allow-unauthenticated -q -y install $PACKAGES >> $LOG 2>&1; then
    echo "{\"changed\": true, \"msg\": \"installed $PACKAGES\"}"
    exit 0
else
    echo "{\"failed\": true, \"msg\": \"install $PACKAGES failed - see $LOG\"}"
    exit 1
fi
