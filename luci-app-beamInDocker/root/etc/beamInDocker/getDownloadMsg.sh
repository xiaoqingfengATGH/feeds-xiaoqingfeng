#!/bin/sh

. /etc/beamInDocker/downloadCommon.sh

if [ ! -r $DOWNLOAD_PROGRESS ]; then
	exit 1
fi

total_lines=$(cat $DOWNLOAD_PROGRESS | wc -l)
last_stateLine=$(cat $DOWNLOAD_PROGRESS | grep == -n | tail -n 1 | awk -F: '{print $1}')
state_singal=$(cat $DOWNLOAD_PROGRESS | grep == -n | tail -n 1 | awk '{print $2}')
current_log_lines=$(echo $total_lines - $last_stateLine | bc)


if [ `echo $state_singal|grep ^D` ]; then
	echo "正在下载镜像..."
elif [ `echo $state_singal|grep ^M` ]; then
	echo "正在校验下载镜像..."
elif [ `echo $state_singal|grep ^U` ]; then
	echo "正在解压并加载到Docker..."
elif [ `echo $state_singal|grep ^I` ]; then
	echo "正在标记镜像..."
fi
cat $DOWNLOAD_PROGRESS | tail -n $current_log_lines
