#!/bin/sh

if [ ! -f "/etc/AdGuardHome/AdGuardHome.yaml" ];
then
	/etc/AdGuardHome/updateAdGuardHomeIP.sh
fi
/usr/bin/AdGuardHome/AdGuardHome -c /etc/AdGuardHome/AdGuardHome.yaml
