#!/bin/sh
INSTALL_LOC=/etc/dnsmasq-china-list
$INSTALL_LOC/refreshConf.sh
$INSTALL_LOC/flush.sh
echo dnsmasq_china_list enabled.
