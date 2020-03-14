#!/bin/bash

LIST_FILE_PREFIX="chnlist_"
CONF_DIR=/etc/dnsmasq_china_list
source conflist.sh

echo "Removing old configurations..."
#for _conf in "${CONF_WITH_SERVERS[@]}" "${CONF_SIMPLE[@]}"; do
#  rm -f /etc/dnsmasq.d/"$_conf"*.conf
#done

rm -f /etc/dnsmasq.d/"$LIST_FILE_PREFIX"*.conf
echo "All dnsmasq_china_list conf removed."
