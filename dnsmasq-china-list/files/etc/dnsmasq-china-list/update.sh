#!/bin/sh
INSTALL_LOC=/etc/dnsmasq-china-list
$INSTALL_LOC/downloadConf.sh
$INSTALL_LOC/refreshConf.sh
$INSTALL_LOC/flush.sh
echo dnsmasq_china_list updated.
