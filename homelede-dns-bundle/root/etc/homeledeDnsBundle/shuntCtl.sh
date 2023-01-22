#!/bin/sh

SHUNT_BIN=/usr/bin/chinadns-ng
SHUNT_CONF=/etc/config/chinadns-ng
SHUNT_CONFIGURATION=homeledeDnsBundle

function startShuntDns()
{
	local pid=$(statusShuntDns)
	if [ "$pid" != "0" ]; then
		echo chinadns-ng has already run on pid $pid;
		return 1
	else
		create_chnroute_ipset
		local inStartUpScript=$(type -t procd_open_instance)
		if [ ! -z $inStartUpScript ]; then
			#在启动脚本中，使用procd启动
			start_chinadns_ng chinadns-ng
			echo Started shuntDns using procd.
		else
			#非启动脚本中，自行启动
			start_chinadns_ng_direct chinadns-ng
		fi
		return $?
	fi

}

function statusShuntDns()
{	local shuntDnsPort=$(getUciConfig chinadns-ng chinadns-ng bind_port 5053)
	local status=$(netstat -lnptu | grep chinadns-ng | grep $shuntDnsPort | cut -d "/" -f 1 | awk '{print $6}')
	if [ ! -z "$status" ]; then
		echo "$status"
	else
		echo "0"
	fi
	return 0
}

function stopShuntDns()
{
	local pid=$(statusShuntDns)
	destroy_chnroute_ipset
	if [ "$pid" != "0" ]; then
		echo "$pid" | while read line
		do
			kill -9 $line
			echo Killed chinadns-ng process with pid $line
		done
		return $?
	else
	    echo chinadns-ng has already stopped.
		return 1
	fi
}

###########################################################

append_param() {
	local section="$1"
	local option="$2"
	local switch="$3"
	local default="$4"
	
	local _loctmp=$(getUciConfig chinadns-ng "$section" "$option" "$default")
	
	#config_get _loctmp "$section" "$option" "$default"
	[ -n "$_loctmp" ] || return 0
	procd_append_param command "$switch" "$_loctmp"
}

append_bool() {
	local section="$1"
	local option="$2"
	local value="$3"
	local default="$4"
	
	local _loctmp=$(getUciConfigAsBool chinadns-ng "$section" "$option" "$default")
	[ "$_loctmp" = 1 ] || return 0
	procd_append_param command "$value"
}

append_param_if_neq() {
	local section="$1"
	local option="$2"
	local switch="$3"
	local compare="$4"
	local _loctmp=$(getUciConfig chinadns-ng "$section" "$option")
	[ -n "$_loctmp" ] || return 0
	[ "$_loctmp" != "$compare" ] || return 0
	procd_append_param command "$switch" "$_loctmp"
}

is_exist_ipset() {
	ipset list -n $1 &>/dev/null
}

create_ipv4_ipset() {
	local ipset_name=$(getUciConfig chinadns-ng $1 "ipset_name4" "chnroute")

	if is_exist_ipset $ipset_name; then
		ipset flush $ipset_name
	else
		ipset create $ipset_name hash:net hashsize 64 family inet
	fi

	# import ipv4 chnroute
	ipset restore <<- EOF
		$(cat /etc/chinadns-ng/chnroute.txt | sed "s/^/add $ipset_name /")
	EOF
}

create_ipv6_ipset() {
	local ipset_name=$(getUciConfig chinadns-ng $1 "ipset_name6" "chnroute6")

	if is_exist_ipset $ipset_name; then
		ipset flush $ipset_name
	else
		ipset create $ipset_name hash:net hashsize 64 family inet6
	fi

	# import ipv6 chnroute
	ipset restore <<- EOF
		$(cat /etc/chinadns-ng/chnroute6.txt | sed "s/^/add $ipset_name /")
	EOF
}

create_chnroute_ipset() {
	create_ipv4_ipset chinadns-ng
	create_ipv6_ipset chinadns-ng
}

destroy_chnroute_ipset() {
	destroy_ipv4_ipset chinadns-ng
	destroy_ipv6_ipset chinadns-ng
}

destroy_ipset() {
	ipset flush $1 2>/dev/null
	ipset destroy $1 2>/dev/null
}

destroy_ipv4_ipset() {
	local ipset_name=$(getUciConfig chinadns-ng $1 "ipset_name4" "chnroute")
	destroy_ipset $ipset_name
}

destroy_ipv6_ipset() {
	local ipset_name=$(getUciConfig chinadns-ng $1 "ipset_name6" "chnroute6")
	destroy_ipset $ipset_name
}

start_chinadns_ng() {
	procd_open_instance homeledeDnsBundleShuntDns
	procd_set_param respawn
	procd_set_param stdout 1
	procd_set_param stderr 1
	procd_set_param nice -5
	procd_set_param file /etc/config/chinadns-ng
	procd_set_param limits nofile="1048576 1048576"
	procd_set_param command /usr/bin/chinadns-ng
	append_param $1 bind_addr "-b"
	append_param $1 bind_port "-l"
	append_param $1 china_dns "-c"
	append_param $1 trust_dns "-t"
	append_param_if_neq $1 ipset_name4 "-4" "chnroute"
	append_param_if_neq $1 ipset_name6 "-6" "chnroute6"
	append_param $1 gfwlist_file "-g"
	append_param $1 chnlist_file "-m"
	append_param_if_neq $1 timeout_sec "-o" "5"
	append_param_if_neq $1 repeat_times "-p" "1"
	append_bool $1 chnlist_first "-M"
	append_bool $1 no_ipv6 "-N"
	append_bool $1 fair_mode "-f"
	append_bool $1 reuse_port "-r"
	append_bool $1 noip_as_chnip "-n"
	append_bool $1 verbose "-v"
	procd_close_instance
}

###########################################################

append_param_direct()
{
	local section="$1"
	local option="$2"
	local switch="$3"
	local default="$4"
	
	local _loctmp=$(getUciConfig chinadns-ng "$section" "$option" "$default")
	[ -n "$_loctmp" ] || return 0
	echo -n "$switch" "$_loctmp"
}

append_param_if_neq_direct() {
	local section="$1"
	local option="$2"
	local switch="$3"
	local compare="$4"
	local _loctmp=$(getUciConfig chinadns-ng "$section" "$option")
	[ -n "$_loctmp" ] || return 0
	[ "$_loctmp" != "$compare" ] || return 0
	echo -n "$switch" "$_loctmp"
}

append_bool_direct() {
	local section="$1"
	local option="$2"
	local value="$3"
	local default="$4"
	
	local _loctmp=$(getUciConfigAsBool chinadns-ng "$section" "$option" "$default")
	[ "$_loctmp" = 1 ] || return 0
	echo -n "$value"
}

start_chinadns_ng_direct()
{
	local PARAM="";
	local temp=$(append_param_direct $1 bind_addr "-b")
	PARAM="$PARAM $temp"
	
	temp=$(append_param_direct $1 bind_port "-l")
	PARAM="$PARAM $temp"
	
	temp=$(append_param_direct $1 china_dns "-c")
	PARAM="$PARAM $temp"
	
	temp=$(append_param_direct $1 trust_dns "-t")
	PARAM="$PARAM $temp"
	
	temp=$(append_param_if_neq_direct $1 ipset_name4 "-4" "chnroute")
	PARAM="$PARAM $temp"
	
	temp=$(append_param_if_neq_direct $1 ipset_name6 "-6" "chnroute6")
	PARAM="$PARAM $temp"
	
	temp=$(append_param_direct $1 gfwlist_file "-g")
	PARAM="$PARAM $temp"
	
	temp=$(append_param_direct $1 chnlist_file "-m")
	PARAM="$PARAM $temp"
	
	temp=$(append_param_if_neq_direct $1 timeout_sec "-o" "5")
	PARAM="$PARAM $temp"
	
	temp=$(append_param_if_neq_direct $1 repeat_times "-p" "1")
	PARAM="$PARAM $temp"

	temp=$(append_param_direct $1 chnlist_first "-M")
	PARAM="$PARAM $temp"
	
	temp=$(append_param_direct $1 no_ipv6 "-N")
	PARAM="$PARAM $temp"
	
	temp=$(append_param_direct $1 fair_mode "-f")
	PARAM="$PARAM $temp"
	
	#append_bool $1 reuse_port "-r"
	
	temp=$(append_param_direct $1 noip_as_chnip "-n")
	PARAM="$PARAM $temp"
	
	temp=$(append_param_direct $1 verbose "-v")
	PARAM="$PARAM $temp"
	
	#echo "nohup $SHUNT_BIN$PARAM > /dev/null 2>&1 &"
	eval "nohup $SHUNT_BIN$PARAM > /dev/null 2>&1 &"
	echo Started shuntDns using nohup.
}