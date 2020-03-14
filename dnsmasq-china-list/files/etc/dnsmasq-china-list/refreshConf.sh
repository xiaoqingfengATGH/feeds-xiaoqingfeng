#!/bin/bash

LIST_FILE_PREFIX="chnlist_"
CONF_DIR=/etc/dnsmasq-china-list/template
source conflist.sh
source dnslist.sh

./clearConf.sh

echo "Installing new configurations..."
for _conf in "${CONF_SIMPLE[@]}"; do
  cp "$CONF_DIR/$_conf.conf" "/etc/dnsmasq.d/$LIST_FILE_PREFIX$_conf.conf"
done

for _server in "${SERVERS[@]}"; do
  for _conf in "${CONF_WITH_SERVERS[@]}"; do
    cp "$CONF_DIR/$_conf.conf" "/etc/dnsmasq.d/$LIST_FILE_PREFIX$_conf.$_server.conf"
  done

  sed -i "s|^\(server.*\)/[^/]*$|\1/$_server|" /etc/dnsmasq.d/*."$_server".conf
done
