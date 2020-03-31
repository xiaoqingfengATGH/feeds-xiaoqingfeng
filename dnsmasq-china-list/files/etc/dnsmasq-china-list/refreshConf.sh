#!/bin/bash

INSTALL_LOC=/etc/dnsmasq-china-list
TARGET_LOC=/tmp/dnsmasq.d

LIST_FILE_PREFIX="chnlist_"
CONF_DIR=/etc/dnsmasq-china-list/template
source $INSTALL_LOC/conflist.sh
source $INSTALL_LOC/dnslist.sh

[ ! -d $TARGET_LOC ] && mkdir -p $TARGET_LOC

$INSTALL_LOC/clearConf.sh

echo "Installing new configurations..."
for _conf in "${CONF_SIMPLE[@]}"; do
  cp "$CONF_DIR/$_conf.conf" "$TARGET_LOC/$LIST_FILE_PREFIX$_conf.conf"
done

for _server in "${SERVERS[@]}"; do
  for _conf in "${CONF_WITH_SERVERS[@]}"; do
    cp "$CONF_DIR/$_conf.conf" "$TARGET_LOC/$LIST_FILE_PREFIX$_conf.$_server.conf"
  done

  sed -i "s|^\(server.*\)/[^/]*$|\1/$_server|" $TARGET_LOC/*."$_server".conf
done
