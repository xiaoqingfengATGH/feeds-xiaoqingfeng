#!/bin/sh

DNSMASQ_CONFIGURATION=dhcp

function startDnsmasq()
{
	local pid=$(statusDnsmasq)
	if [ "$pid" != "0" ]; then
		echo Dnsmasq has already run on pid $pid;
		return 1
	else
		/etc/init.d/dnsmasq start
		return $?
	fi

}

function statusDnsmasq()
{
	local status=$(netstat -lnptu | grep dnsmasq | sed -n "1p" | cut -d "/" -f 1 | awk '{print $7}')
	if [ ! -z $status ]; then
		echo $status
	else
		echo "0"
	fi
	return 0
}

function stopDnsmasq()
{
	local pid=$(statusDnsmasq)
	if [ "$pid" != "0" ]; then
		/etc/init.d/dnsmasq stop
		return $?
	else
	    echo Dnsmasq has already stopped.
		return 1
	fi
}

