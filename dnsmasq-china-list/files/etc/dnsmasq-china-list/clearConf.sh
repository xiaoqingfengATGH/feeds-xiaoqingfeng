#!/bin/bash

LIST_FILE_PREFIX="chnlist_"
INSTALL_LOC=/etc/dnsmasq-china-list
TARGET_LOC=/tmp/dnsmasq.d
source $INSTALL_LOC/conflist.sh

echo "Removing old configurations..."
#for _conf in "${CONF_WITH_SERVERS[@]}" "${CONF_SIMPLE[@]}"; do
#  rm -f $TARGET_LOC/"$_conf"*.conf
#done

rm -f $TARGET_LOC/"$LIST_FILE_PREFIX"*.conf
echo "All dnsmasq_china_list conf removed."
