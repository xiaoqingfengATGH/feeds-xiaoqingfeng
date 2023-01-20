#!/bin/sh

AD_BLOCK_BIN=/etc/AdGuardHome/startAdGuardHome.sh
AD_BLOCK_CONF=/etc/AdGuardHome/AdGuardHome.yaml
AD_BLOCK_CONFIGURATION=homeledeDnsBundle

function startAdBlock()
{
	local pid=$(statusAdBlock)
	if [ "$pid" != "0" ]; then
		echo AdGuardHome has already run on pid $pid;
		return 1
	else
		prepareAdBlockConfig
		# AdGuardHome 具备自有的守护策略，无需使用procd（procd并不能管理AdGuardHome）
		#local inStartUpScript=$(type -t procd_open_instance)
		#if [ ! -z $inStartUpScript ]; then
		#	#在启动脚本中，使用procd启动
		#	procd_open_instance homeledeDnsBundleAdBlock
		#	procd_set_param respawn
		#	# pass config to script on start
		#	procd_set_param command $AD_BLOCK_BIN
		#	procd_close_instance
		#	echo Started adblock using procd.
		#else
			#非启动脚本中，自行启动	
			local stResult=$(nohup $AD_BLOCK_BIN > /dev/null 2>&1 &)
			echo Started adblock using nohup.
		#fi
		return $stResult
	fi

}

function statusAdBlock()
{
	local status=$(netstat -lnptu | grep AdGuardHome | sed -n "1p" | cut -d "/" -f 1 | awk '{print $7}')
	if [ ! -z $status ]; then
		echo $status
	else
		echo "0"
	fi
	return 0
}

function stopAdBlock()
{
	local pid=$(statusAdBlock)
	if [ "$pid" != "0" ]; then
		kill -9 $pid
		echo Killed AdGuardHome process with pid $pid
		return $?
	else
	    echo AdGuardHome has already stopped.
		return 1
	fi
}

function prepareAdBlockConfig()
{
	local webUIPort=$(getUciConfig $AD_BLOCK_CONFIGURATION adBlock webUIPort 3000)
	local dnsPort=$(getUciConfig $AD_BLOCK_CONFIGURATION adBlock port 53)
	
	replaceLine $AD_BLOCK_CONF "^bind_port:.*$" "bind_port: $webUIPort"
	replaceLine $AD_BLOCK_CONF "\ \ port:" "\ \ port: $dnsPort"
}

#AdBlock 开启时，dnsmasq为54，AdGuardHome上游为dnsmasq

#AdBlock关闭后，确认dnsmasq为53入口

