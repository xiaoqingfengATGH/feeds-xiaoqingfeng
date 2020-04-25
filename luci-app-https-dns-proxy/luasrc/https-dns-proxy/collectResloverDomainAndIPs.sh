#!/bin/bash
reslovers=()
resloverdomains=()
count=0
function lookupSingleIp(){
for ip in $@;
do
	[[ -z $ip ]] && continue;
		panduan=`nslookup $ip 119.29.29.29| egrep 'name.*='`
#		if [ ! -z $panduan ]; then
#			domain=`nslookup $ip 119.29.29.29| egrep 'name.*=' |  awk '{if(NR==1) print $NF}'`  #查询cname地址，如果只需查询IP地址可屏蔽这一句，使用下面的方法
#		else
			domain=`nslookup $ip 119.29.29.29| egrep 'Address:' |  awk '{if(NR==2) print $NF}'` #查询IP地址
#		fi
	echo  "$domain"
done
}
for file in ./providers/*
do 
	reslovers[count]=`cat $file | grep 'resolver_url' | cut -d '"' -f2`
	count+=1
done
echo ${#reslovers[@]} reslovers collected.
count=0
for reslover in ${reslovers[*]}
do
	resloverdomains[count]=`echo $reslover | cut -d '/' -f3`
	echo ${resloverdomains[count]}
	count+=1
done
for domain in ${resloverdomains[@]}
do
	lookupSingleIp $domain
done
