#!/bin/sh
function uci_config_foreach()
{
	local configName=$1
    local sectionType=$2
    local callback=$3
	
	local ref=$(uci -X show $configName)
    if [ -z "$ref" ]; then
        return 1
    fi
	
	ref=$(uci -X show $configName | grep =$sectionType$ | cut -d "=" -f 1)
	echo "$ref" | while read line
	do
		#local lineLen=${#line}
		#local vals=$(uci -X show $configName | grep -E "^$line[.]{1}")
		#$3 $lineLen "$vals"
		$3 ${line}
	done
}
# uci_config_foreach 回调示例
# 例子：uci_config_foreach smartdns server exampleResloveValues

function exampleResloveValues()
{
	local prefix=$1
	echo $prefix
	uci_config_get test $prefix enabled "2"
	
}

# uci_config_foreach 回调示例（旧）
# 这里一次性将所有配置返回，在一个函数中处理
function exampleResloveValues1()
{
	local prefixLen=$1
	local vals=$2
	echo "$vals"
	echo "$vals" | while read line
	do
		local pair=${line:$prefixLen}
		local key=$(echo $pair | cut -d "=" -f 1)
		local val=$(echo $pair | cut -d "=" -f 2 | sed "s/'//g")
		echo "Got key:$key val:$val"
	done
}

# 平替 functions.sh config_get
function uci_config_get()
{
	local export_var=$1
	local configPrefix=$2
	local optionKey=$3
    local defaultVal=$4
	local result=$(uci get ${configPrefix}.${optionKey} 2> /dev/null) 
	#echo ${result:-${defaultVal}}
	eval export -- "${export_var}=\${result:-\${defaultVal}}"
}

#平替 functions.sh config_get_bool
function uci_config_get_bool()
{
	local export_var=$1
	local configPrefix=$2
    local defaultVal=$4
	
	local conf=$(uci_config_get $@)
	local trans=$(trans_bool $conf $4)
	#echo -n $trans
	eval export -- "${export_var}=\${trans:-\${defaultVal}}"
}

function getUciConfig(){
    local configName=$1
    local sectionType=$2
    local optionKey=$3
    local defaultVal=$4

	#echo $configName
    local ref=$(uci -X show $configName)
	#echo "|$ref|"
    if [ -z "$ref" ]; then
        return 1
    fi

    ref=$(uci -X show $configName | grep =${sectionType}$ | cut -d "=" -f 1)
	if [ -z $ref ]; then
		ref=$(uci -X show $configName | grep ${sectionType}= | cut -d "=" -f 1)
	fi
	#echo "#$ref#"
	#echo $ref.$optionKey
	
    local getVal=$(uci -q get ${ref}.${optionKey})
	echo ${getVal:-${defaultVal}}
	#echo "${optionKey}=\${getVal:-\${defaultVal}}"
	eval export -- "${optionKey}=\${getVal:-\${defaultVal}}"
    return 0
}

function getUciConfigAsBool()
{
	local conf=$(getUciConfig $@)
	local trans=$(trans_bool $conf $4)
	echo -n $trans
}

function setUciConfig(){
    local configName=$1
    local sectionType=$2
    local optionKey=$3
    local valToWrite=$4

    local ref=$(uci -X show $configName)

    if [ -z "$ref" ]; then
        return 1
    fi
	
	ref=$(uci -X show $configName | grep =${sectionType}$ | cut -d "=" -f 1)
	if [ -z $ref ]; then
		ref=$(uci -X show $configName | grep ${sectionType}= | cut -d "=" -f 1)
	fi
	
    eval "uci set $ref.$optionKey=$valToWrite"
    return $?
}

function removeUciConfig(){
    local configName=$1
    local sectionType=$2
    local optionKey=$3

    local ref=$(uci -X show $configName)

    if [ -z "$ref" ]; then
        return 1
    fi
	
	ref=$(uci -X show $configName | sed -n "1p" | grep $sectionType | cut -d "=" -f 1)
	if [ -z $ref ]; then
		ref=$(uci -X show $configName | grep $sectionType= | cut -d "=" -f 1)
	fi
	
    uci delete $ref.$optionKey > /dev/null 2>&1
    return $?
}

# trans_bool <value> [<default>]
trans_bool() {
	local _tmp="$1"
	case "$_tmp" in
		1|on|true|yes|enabled) _tmp=1;;
		0|off|false|no|disabled) _tmp=0;;
		*) _tmp="$2";;
	esac
	echo -n "$_tmp"
}