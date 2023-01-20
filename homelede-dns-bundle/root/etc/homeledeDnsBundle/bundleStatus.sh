source /etc/homeledeDnsBundle/uciconfig_util.sh
source /etc/homeledeDnsBundle/file_replace_util.sh

source /etc/homeledeDnsBundle/adBlockCtrl.sh
source /etc/homeledeDnsBundle/dnsmasqCtl.sh
source /etc/homeledeDnsBundle/shuntCtl.sh
source /etc/homeledeDnsBundle/domesticDnsCtl.sh
source /etc/homeledeDnsBundle/overseasDnsCtl.sh

adBlockCurrentState=$(statusAdBlock)
[ "${adBlockCurrentState}" == "0" ] &&  adBlockCurrentState="已停止" || adBlockCurrentState="运行中"
shuntDnsCurrentState=$(statusShuntDns)
[ "${shuntDnsCurrentState}" == "0" ] &&  shuntDnsCurrentState="已停止" || shuntDnsCurrentState="运行中"
domesticDnsCurrentState=$(statusDomesticDns)
[ "${domesticDnsCurrentState}" == "0" ] &&  domesticDnsCurrentState="已停止" || domesticDnsCurrentState="运行中"
overseasDnsCurrentState=$(statusOverseasDns)
[ "${overseasDnsCurrentState}" == "0" ] &&  overseasDnsCurrentState="已停止" || overseasDnsCurrentState="运行中"
dnsmasqCurrentState=$(statusDnsmasq)
[ "${dnsmasqCurrentState}" == "0" ] &&  dnsmasqCurrentState="已停止" || dnsmasqCurrentState="运行中"

(
cat <<EOF
{
	"adBlock": "${adBlockCurrentState}",
	"dnsmasq": "${dnsmasqCurrentState}",
	"shunt": "${shuntDnsCurrentState}",
	"domesticDns": "${domesticDnsCurrentState}",
	"overseasDns": "${overseasDnsCurrentState}"
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