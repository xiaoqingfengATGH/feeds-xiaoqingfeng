#!/bin/sh

ROUTER_IP=$(ifconfig br-lan | grep 'inet addr' | sed 's/^.*addr://g' | cut -d ' ' -f 1)
IP_INCONFIG=$ROUTER_IP

if [ -f "/etc/AdGuardHome/AdGuardHome.yaml" ];
then
IP_IN_CONFIG=cat /etc/AdGuardHome/AdGuardHome.yaml | grep "bind_host:" | sed -n 1p | cut -d ':' -f 2 | sed -r 's/^[ ]+//g'
fi

if [ ! -f "/etc/AdGuardHome/AdGuardHome.yaml" ];
then
        /etc/AdGuardHome/initConfig.sh
fi

if [ "$IP_IN_CONFIG" != "$ROUTER_IP" ];
then
echo "Router lan ip changed. Automatic change ip address in /etc/AdGuardHome/AdGuardHome.yaml."
sed -i "s/bind_host: "$IP_IN_CONFIG"/bind_host: "$ROUTER_IP"/" /etc/AdGuardHome/AdGuardHome.yaml
echo "Bind address in /etc/AdGuardHome/AdGuardHome.yaml has been changed to "$ROUTER_IP"."
fi

/usr/bin/AdGuardHome/AdGuardHome -c /etc/AdGuardHome/AdGuardHome.yaml
