#!/bin/sh

DOMESTIC_BIN=/usr/sbin/smartdns
DOMESTIC_CONF=/etc/config/smartdns
DOMESTIC_CONFIGURATION=homeledeDnsBundle

SMARTDNS_CONF_DIR="/etc/smartdns"
SMARTDNS_VAR_CONF_DIR="/var/etc/smartdns"
SMARTDNS_CONF="$SMARTDNS_VAR_CONF_DIR/smartdns.conf"
ADDRESS_CONF="$SMARTDNS_CONF_DIR/address.conf"
BLACKLIST_IP_CONF="$SMARTDNS_CONF_DIR/blacklist-ip.conf"
CUSTOM_CONF="$SMARTDNS_CONF_DIR/custom.conf"
SMARTDNS_CONF_TMP="${SMARTDNS_CONF}.tmp"

function startDomesticDns()
{
	local pid=$(statusDomesticDns)
	if [ "$pid" != "0" ]; then
		echo Smartdns has already run on pid $pid;
		return 1
	else
		start_smartdns "smartdns"
		return $?
	fi

}

function statusDomesticDns()
{	local shuntDnsPort=$(getUciConfig smartdns smartdns port 6053)
	local status=$(netstat -lnptu | grep smartdns | grep $shuntDnsPort | cut -d "/" -f 1 | awk '{print $6}')
	if [ ! -z "$status" ]; then
		echo "$status"
	else
		echo "0"
	fi
	return 0
}

function stopDomesticDns()
{
	local pid=$(statusDomesticDns)
	if [ "$pid" != "0" ]; then
		echo "$pid" | while read line
		do
			kill -9 $line
			echo Killed smartdns process with pid $line
		done
		return $?
	else
	    echo smartdns has already stopped.
		return 1
	fi
}

###########################################################

get_tz()
{
	SET_TZ=""

	[ -e "/etc/localtime" ] && return

	for tzfile in /etc/TZ /var/etc/TZ
	do
		[ -e "$tzfile" ] || continue
		tz="$(cat $tzfile 2>/dev/null)"
	done

	[ -z "$tz" ] && return

	SET_TZ=$tz
}

conf_append()
{
	echo "$1 $2" >> $SMARTDNS_CONF_TMP
}

load_server()
{

	local section="$1"
	local ADDITIONAL_ARGS=""
	local DNS_ADDRESS=""

	uci_config_get_bool enabled "$section" "enabled" "1"
	uci_config_get port "$section" "port" ""
	uci_config_get type "$section" "type" "udp"
	uci_config_get ip "$section" "ip" ""
	uci_config_get tls_host_verify "$section" "tls_host_verify" ""
	uci_config_get host_name "$section" "host_name" ""
	uci_config_get http_host "$section" "http_host" ""
	uci_config_get server_group "$section" "server_group" ""
	uci_config_get blacklist_ip "$section" "blacklist_ip" "0"
	uci_config_get check_edns "$section" "check_edns" "0"
	uci_config_get spki_pin "$section" "spki_pin" ""
	uci_config_get addition_arg "$section" "addition_arg" ""

	[ "$enabled" = "0" ] && return

	if [ -z "$ip" ] || [ -z "$type" ]; then
		return
	fi

	SERVER="server"
	if [ "$type" = "tcp" ]; then
		SERVER="server-tcp"
	elif [ "$type" = "tls" ]; then
		SERVER="server-tls"
	elif [ "$type" = "https" ]; then
		SERVER="server-https"
	fi

	if echo "$ip" | grep ":" | grep -q -v "https://" >/dev/null 2>&1; then
		if ! echo "$ip" | grep -q "\\[" >/dev/null 2>&1; then
			ip="[$ip]"
		fi
	fi

	[ -z "$tls_host_verify" ] || ADDITIONAL_ARGS="$ADDITIONAL_ARGS -tls-host-verify $tls_host_verify"
	[ -z "$host_name" ] || ADDITIONAL_ARGS="$ADDITIONAL_ARGS -host-name $host_name"
	[ -z "$http_host" ] || ADDITIONAL_ARGS="$ADDITIONAL_ARGS -http-host $http_host"
	[ -z "$server_group" ] || ADDITIONAL_ARGS="$ADDITIONAL_ARGS -group $server_group"
	[ "$blacklist_ip" = "0" ] || ADDITIONAL_ARGS="$ADDITIONAL_ARGS -blacklist-ip"
	[ "$check_edns" = "0" ] || ADDITIONAL_ARGS="$ADDITIONAL_ARGS -check-edns"
	[ -z "$spki_pin" ] || ADDITIONAL_ARGS="$ADDITIONAL_ARGS -spki-pin $spki_pin"

	if [ -z "$port" ]; then
		DNS_ADDRESS="$ip"
	else
		DNS_ADDRESS="$ip:$port"
	fi

	[ "$type" = "https" ] && DNS_ADDRESS="$ip"

	conf_append "$SERVER" "$DNS_ADDRESS $ADDITIONAL_ARGS $addition_arg"
}

###########################################################

function start_smartdns()
{
	local section="$1"
	args=""

	mkdir -p $SMARTDNS_VAR_CONF_DIR
	rm -f $SMARTDNS_CONF_TMP

	server_name=$(getUciConfig smartdns smartdns server_name 'HomeLedeDNS')
	[ -z "$server_name" ] || conf_append "server-name" "$server_name"

	coredump=$(getUciConfig smartdns smartdns coredump "0")
	[ "$coredump" = "1" ] && COREDUMP="1"

	uci_config_get port $section "port" "6053"
	uci_config_get ipv6_server $section "ipv6_server" "0"
	uci_config_get tcp_server $section "tcp_server" "0"
	
	if [ "$ipv6_server" = "1" ]; then
		conf_append "bind" "[::]:$port"
	else
		conf_append "bind" ":$port"
	fi

	[ "$tcp_server" = "1" ] && {
		if [ "$ipv6_server" = "1" ]; then
			conf_append "bind-tcp" "[::]:$port"
		else
			conf_append "bind-tcp" ":$port"
		fi
	}

	uci_config_get dualstack_ip_selection "$section" "dualstack_ip_selection" "0"
	[ "$dualstack_ip_selection" = "1" ] && conf_append "dualstack-ip-selection" "yes"

	uci_config_get prefetch_domain "$section" "prefetch_domain" "0"
	[ "$prefetch_domain" = "1" ] && conf_append "prefetch-domain" "yes"

	uci_config_get serve_expired "$section" "serve_expired" "0"
	[ "$serve_expired" = "1" ] && conf_append "serve-expired" "yes"

	SMARTDNS_PORT="$port"

	uci_config_get cache_size "$section" "cache_size" ""
	[ -z "$cache_size" ] || conf_append "cache-size" "$cache_size"

	uci_config_get rr_ttl "$section" "rr_ttl" ""
	[ -z "$rr_ttl" ] || conf_append "rr-ttl" "$rr_ttl"

	uci_config_get rr_ttl_min "$section" "rr_ttl_min" ""
	[ -z "$rr_ttl_min" ] || conf_append "rr-ttl-min" "$rr_ttl_min"

	uci_config_get rr_ttl_max "$section" "rr_ttl_max" ""
	[ -z "$rr_ttl_max" ] || conf_append "rr-ttl-max" "$rr_ttl_max"

	uci_config_get log_size "$section" "log_size" "64K"
	[ -z "$log_size" ] || conf_append "log-size" "$log_size"

	uci_config_get log_num "$section" "log_num" "1"
	[ -z "$log_num" ] || conf_append "log-num" "$log_num"

	uci_config_get log_level "$section" "log_level" "error"
	[ -z "$log_level" ]|| conf_append "log-level" "$log_level"

	uci_config_get log_file "$section" "log_file" ""
	[ -z "$log_file" ] || conf_append "log-file" "$log_file"

	uci_config_foreach smartdns "server" load_server

	{
		echo "cache-persist yes"
		echo "cache-file /tmp/smartdns.cache"
	
		echo "conf-file $ADDRESS_CONF"
		echo "conf-file $BLACKLIST_IP_CONF"
		echo "conf-file $CUSTOM_CONF"
	} >> $SMARTDNS_CONF_TMP
	mv $SMARTDNS_CONF_TMP $SMARTDNS_CONF

	local inStartUpScript=$(type -t procd_open_instance)
	if [ ! -z $inStartUpScript ]; then
		#在启动脚本中，使用procd启动
		procd_open_instance "homeledeDnsBundleDomesticDns"
		[ "$COREDUMP" = "1" ] && {
			args="$args -S"
			procd_set_param limits core="unlimited"
		}

		get_tz
		[ -z "$SET_TZ" ] || procd_set_param env TZ="$SET_TZ"

		procd_set_param command $DOMESTIC_BIN -f -c $SMARTDNS_CONF $args
		[ "$RESPAWN" = "1" ] &&	procd_set_param respawn ${respawn_threshold:-3600} ${respawn_timeout:-5} ${respawn_retry:-5}
		procd_set_param file "$SMARTDNS_CONF"
		procd_close_instance
		echo Started domestic dns using procd.
	else
		#非启动脚本中，自行启动
		eval "nohup $DOMESTIC_BIN -f -c $SMARTDNS_CONF $args > /dev/null 2>&1 &"
		echo Started domestic dns using nohup.
	fi
}