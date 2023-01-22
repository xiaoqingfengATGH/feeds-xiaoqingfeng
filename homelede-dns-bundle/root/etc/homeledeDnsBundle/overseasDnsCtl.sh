#!/bin/sh

OVERSEAS_BIN=/usr/sbin/dnscrypt-proxy
OVERSEAS_CONF=/etc/dnscrypt-proxy2/dnscrypt-proxy.toml
OVERSEAS_CONFIGURATION=homeledeDnsBundle

function startOverseasDns()
{
	local pid=$(statusOverseasDns)
	if [ "$pid" != "0" ]; then
		echo DnscryptProxy2 has already run on pid $pid;
		return 1
	else
		prepareOverseasDnsConfig
		local inStartUpScript=$(type -t procd_open_instance)
		if [ ! -z $inStartUpScript ]; then
			#在启动脚本中，使用procd启动
			procd_open_instance homeledeDnsBundleOverseasDns
			procd_set_param respawn ${respawn_threshold:-3600} ${respawn_timeout:-5} ${respawn_retry:-5}
			procd_set_param stdout 1
			procd_set_param stderr 1
			# pass config to script on start
			procd_set_param command $OVERSEAS_BIN -config "$OVERSEAS_CONF"
			procd_set_param file "$OVERSEAS_CONF"
			procd_close_instance
			echo Started overseasDns using procd.
		else
			#非启动脚本中，自行启动
			nohup $OVERSEAS_BIN -config $OVERSEAS_CONF > /dev/null 2>&1 &
			echo Started overseasDns using nohup.
		fi
		return $?
	fi

}

function statusOverseasDns()
{
	local status=$(netstat -lnptu | grep dnscrypt-prox | sed -n "1p" | cut -d "/" -f 1 | awk '{print $7}')
	if [ ! -z $status ]; then
		echo $status
	else
		echo "0"
	fi
	return 0
}

function stopOverseasDns()
{
	local pid=$(statusOverseasDns)
	if [ "$pid" != "0" ]; then
		local inStartUpScript=$(type -t procd_kill)
		if [ ! -z $inStartUpScript ]; then
			procd_running "HomeledeDnsBundle" "homeledeDnsBundleAdBlock" && \
			procd_kill "HomeledeDnsBundle" "homeledeDnsBundleOverseasDns" || \
			echo "Overseas dns has already stopped by procd."
		else
			kill -9 $pid
			echo Killed DnscryptProxy2 process with pid $pid
		fi
		return $?
	else
	    echo DnscryptProxy2 has already stopped.
		return 1
	fi
}

function prepareOverseasDnsConfig()
{
	local dnsPort=$(getUciConfig $OVERSEAS_CONFIGURATION shuntResolution overseasPort 7053)
	replaceLine $OVERSEAS_CONF "^listen_addresses = .*$" "listen_addresses = ['127.0.0.1:$dnsPort']"
}

