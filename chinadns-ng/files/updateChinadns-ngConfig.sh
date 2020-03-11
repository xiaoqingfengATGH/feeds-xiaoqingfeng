#!/bin/sh
## IPv4 路由表
wget https://pexcn.me/daily/chnroute/chnroute.txt -O /etc/chinadns-ng/chnroute.txt
# IPv6 路由表
wget https://pexcn.me/daily/chnroute/chnroute-v6.txt -O /etc/chinadns-ng/chnroute6.txt
# 域名黑名单
wget https://pexcn.me/daily/gfwlist/gfwlist.txt -O /etc/chinadns-ng/gfwlist.txt
# 域名白名单
wget https://pexcn.me/daily/chinalist/chinalist.txt -O /etc/chinadns-ng/chinalist.txt
# 重启程序以触发更新 ipset
/etc/init.d/chinadns-ng restart
