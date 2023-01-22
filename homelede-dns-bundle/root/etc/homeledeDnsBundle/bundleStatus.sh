source /etc/homeledeDnsBundle/uciconfig_util.sh
source /etc/homeledeDnsBundle/file_replace_util.sh

source /etc/homeledeDnsBundle/adBlockCtrl.sh
source /etc/homeledeDnsBundle/dnsmasqCtl.sh
source /etc/homeledeDnsBundle/shuntCtl.sh
source /etc/homeledeDnsBundle/domesticDnsCtl.sh
source /etc/homeledeDnsBundle/overseasDnsCtl.sh

adBlockCurrentState=$(statusAdBlock)
[ "${adBlockCurrentState}" == "0" ] &&  adBlockCurrentState="stopped" || adBlockCurrentState="running"
shuntDnsCurrentState=$(statusShuntDns)
[ "${shuntDnsCurrentState}" == "0" ] &&  shuntDnsCurrentState="stopped" || shuntDnsCurrentState="running"
domesticDnsCurrentState=$(statusDomesticDns)
[ "${domesticDnsCurrentState}" == "0" ] &&  domesticDnsCurrentState="stopped" || domesticDnsCurrentState="running"
overseasDnsCurrentState=$(statusOverseasDns)
[ "${overseasDnsCurrentState}" == "0" ] &&  overseasDnsCurrentState="stopped" || overseasDnsCurrentState="running"
dnsmasqCurrentState=$(statusDnsmasq)
[ "${dnsmasqCurrentState}" == "0" ] &&  dnsmasqCurrentState="stopped" || dnsmasqCurrentState="running"

CONFIGURATION=homeledeDnsBundle

adBlockEnabled=$(getUciConfig ${CONFIGURATION} global "adBlock" 0)
shuntResolutionEnabled=$(getUciConfig ${CONFIGURATION} global "shuntResolution" 0)

[ "${adBlockCurrentState}" == "stopped" ] && [ "${adBlockEnabled}" == "0" ] && adBlockCurrentState="disabled"
[ "${shuntDnsCurrentState}" == "stopped" ] && [ "${shuntResolutionEnabled}" == "0" ] && shuntDnsCurrentState="disabled"
[ "${domesticDnsCurrentState}" == "stopped" ] && [ "${shuntResolutionEnabled}" == "0" ] && domesticDnsCurrentState="disabled"
[ "${overseasDnsCurrentState}" == "stopped" ] && [ "${shuntResolutionEnabled}" == "0" ] && overseasDnsCurrentState="disabled"

(
cat <<EOF
{
	"adBlock": "${adBlockCurrentState}",
	"dnsmasq": "${dnsmasqCurrentState}",
	"shunt": "${shuntDnsCurrentState}",
	"domesticDns": "${domesticDnsCurrentState}",
	"overseasDns": "${overseasDnsCurrentState}",
	"solution": "${adBlockEnabled}${shuntResolutionEnabled}"
}
EOF
)
     
#echo AdBlock state:
#statusAdBlock
#echo Dnsmasq state:
#statusDnsmasq
#echo Shunt state:
#statusShuntDns
#echo DomesticDns state:
#statusDomesticDns
#echo OverseasDns state:
#statusOverseasDns