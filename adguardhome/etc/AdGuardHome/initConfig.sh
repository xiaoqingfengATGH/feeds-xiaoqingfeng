#!/bin/sh

ROUTER_IP=$(ifconfig br-lan | grep 'inet addr' | sed 's/^.*addr://g' | cut -d ' ' -f 1)
echo OpenWrt Router LAN IP is : $ROUTER_IP
if [ -f "/etc/AdGuardHome/AdGuardHome.yaml" ];
then 
cp /etc/AdGuardHome/AdGuardHome.yaml /etc/AdGuardHome/AdGuardHome.yaml.bak
fi
cp /etc/AdGuardHome/AdGuardHome.yaml.template /etc/AdGuardHome/AdGuardHome.yaml
sed -i "s/##ROUTER_IP##/"$ROUTER_IP"/" /etc/AdGuardHome/AdGuardHome.yaml
echo Created new initial AdGuardHome.yaml and set Router IP.
