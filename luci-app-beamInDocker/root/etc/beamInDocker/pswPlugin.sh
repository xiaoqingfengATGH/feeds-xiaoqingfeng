#!/bin/sh

. /etc/beamInDocker/dockerControl.sh

PSW_NODE_NAME="beamInDocker"

function isNodeExist()
{
	local xx=$(uci show passwall | grep $PSW_NODE_NAME | wc -l)
	[ "$xx" -eq 0 ] && return 0 || return 1
}

PSW_NODE_ID=$PSW_NODE_NAME

function addNode()
{
	isNodeExist
	[ $? -eq 0 ] && {
	local item=$(uci add passwall nodes)
	uci batch << EOF
set passwall.$item='nodes'
set passwall.$item.remarks='$PSW_NODE_NAME'
set passwall.$item.type='Socks'
set passwall.$item.port='3129'
set passwall.$item.address='$BEAM_IP'
rename passwall.$item=$PSW_NODE_NAME
EOF
	uci commit passwall
		return 0
	} || {
		return 1
	}
}

function removeNode()
{
	isNodeExist
	[ $? -eq 1 ] && {
		uci delete passwall.$PSW_NODE_ID
		uci commit passwall
	}
}

function setToTcpDefaultAndRestart()
{
	isNodeExist
	[ $? -eq 1 ] && {
		uci set passwall.@global[0].tcp_node='beamInDocker'
		uci commit passwall
		/etc/init.d/passwall restart
	}
}

addNode
setToTcpDefaultAndRestart
