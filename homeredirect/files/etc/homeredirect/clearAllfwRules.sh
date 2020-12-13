#!/bin/bash

fwRC=$(cat /etc/config/firewall | grep rule | wc -l)
fwMI=$(expr $fwRC - 1)
change=0
for ((i=($fwRC);i>=0;i--));
do
	ruleName=$(uci -q get firewall.@rule[$i].name)
	if [ -n ${ruleName} ] && [ "${ruleName:0:3}" == "HR_" ]; then
		uci delete firewall.@rule[$i]
		change=1
	fi
done

[ "$change" == "1" ] && {
	uci commit firewall >/dev/null 2>&1
	[  "withFWRestart" == "$1" ] && /etc/init.d/firewall restart >/dev/null 2>&1
}
