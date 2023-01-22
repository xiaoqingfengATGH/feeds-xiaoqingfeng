#!/bin/sh

source /lib/functions.sh

source /etc/homeledeDnsBundle/uciconfig_util.sh
source /etc/homeledeDnsBundle/file_replace_util.sh

source /etc/homeledeDnsBundle/adBlockCtrl.sh
source /etc/homeledeDnsBundle/shuntCtl.sh
source /etc/homeledeDnsBundle/domesticDnsCtl.sh
source /etc/homeledeDnsBundle/overseasDnsCtl.sh

source /etc/homeledeDnsBundle/processCtrl.sh

source /etc/homeledeDnsBundle/targetProcStates.sh

CONFIGURATION=homeledeDnsBundle

globalEnabled=$(getUciConfig ${CONFIGURATION} global "enabled" 0)

if [ "$globalEnabled" -eq 1 ]; then
	makeSureAllProcessStateAsExpected ${adBlockTargetState} ${shuntDnsTargetState} ${domesticDnsTargetState} ${overseasDnsTargetState}
fi