#!/bin/bash
set -e

INSTALL_LOC=/etc/dnsmasq-china-list
LIST_FILE_PREFIX="chnlist_"

source $INSTALL_LOC/dnslist.sh
source $INSTALL_LOC/conflist.sh

$INSTALL_LOC/downloadConf.sh
$INSTALL_LOC/refreshConf.sh
$INSTALL_LOC/flush.sh
