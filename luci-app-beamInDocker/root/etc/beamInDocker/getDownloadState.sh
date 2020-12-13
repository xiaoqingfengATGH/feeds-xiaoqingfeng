#!/bin/sh

SCRIPT_BASE=/etc/beamInDocker

. /etc/beamInDocker/downloadCommon.sh

PID='NOTEXIST'
if [ -f $DOWNLOAD_PID ]; then
	PID=$(cat $DOWNLOAD_PID)
	#echo Find download process PID： $PID
fi

ProcessExist=$(ps | grep $PID | grep -v grep | wc -l)
if [ $ProcessExist = 1 ]; then
	#echo Downloading process is still running.
	echo 1
	exit 1
else
	#if [ "$PID" != "NOTEXIST" ]; then
		#echo OLD Process $PID does not exist.
	#fi
	echo 0
	exit 0
fi
