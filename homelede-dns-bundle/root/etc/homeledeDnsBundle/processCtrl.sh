#!/bin/sh

function makeSureAllProcessStateAsExpected()
{
	local adBlockTargetState=$1
	local shuntDnsTargetState=$2
	local domesticDnsTargetState=$3
	local overseasDnsTargetState=$4

	local adBlockCurrentState=$(statusAdBlock)
	[ "${adBlockCurrentState}" == "0" ] &&  adBlockCurrentState=0 || adBlockCurrentState=1
	local shuntDnsCurrentState=$(statusShuntDns)
	[ "${shuntDnsCurrentState}" == "0" ] &&  shuntDnsCurrentState=0 || shuntDnsCurrentState=1
	local domesticDnsCurrentState=$(statusDomesticDns)
	[ "${domesticDnsCurrentState}" == "0" ] &&  domesticDnsCurrentState=0 || domesticDnsCurrentState=1
	local overseasDnsCurrentState=$(statusOverseasDns)
	[ "${overseasDnsCurrentState}" == "0" ] &&  overseasDnsCurrentState=0 || overseasDnsCurrentState=1
	
	[ "$(xor $adBlockCurrentState $adBlockTargetState)" == "1" ] && {
		echo AdBlock state mismatch!
		[ "$adBlockTargetState" == "1" ] && {
			startAdBlock
			echo Started AdBlock
		} || {
			stopAdBlock
		}
	}
	[ "$(xor $shuntDnsCurrentState $shuntDnsTargetState)" == "1" ] && {
		echo ShuntDns state mismatch!
		echo CURRENT=${shuntDnsCurrentState} TARGET=${shuntDnsTargetState}
		[ "$shuntDnsTargetState" == "1" ] && {
			startShuntDns
			echo Started ShuntDns
		} || {
			stopShuntDns
		}
	}
	[ "$(xor $domesticDnsCurrentState $domesticDnsTargetState)" == "1" ] && {
		echo DomesticDns state mismatch!
		[ "$domesticDnsTargetState" == "1" ] && {
			startDomesticDns
			echo Started DomesticDns
		} || {
			stopDomesticDns
		}
	}
	[ "$(xor $overseasDnsCurrentState $overseasDnsTargetState)" == "1" ] && {
		echo OverseasDns state mismatch!
		[ "$overseasDnsTargetState" == "1" ] && {
			startOverseasDns
			echo Started OverseasDns
		} || {
			stopOverseasDns
		}
	}
}

function saveProcessExpectedStates()
{	
(
cat <<EOF
adBlockTargetState=$1
shuntDnsTargetState=$2
domesticDnsTargetState=$3
overseasDnsTargetState=$4
EOF
) > /etc/homeledeDnsBundle/targetProcStates.sh
}