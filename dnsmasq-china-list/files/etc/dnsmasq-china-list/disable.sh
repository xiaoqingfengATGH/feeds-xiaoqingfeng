#!/bin/sh

INSTALL_LOC=/etc/dnsmasq-china-list
$INSTALL_LOC/clearConf.sh
$INSTALL_LOC/flush.sh
echo dnsmasq_china_list disabled.
