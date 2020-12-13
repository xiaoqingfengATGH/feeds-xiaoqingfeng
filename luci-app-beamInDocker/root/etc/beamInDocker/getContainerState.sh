#!/bin/sh

. /etc/beamInDocker/dockerControl.sh

isImageExist
[ $? -eq 0 ] && {
	echo 1
	exit 1
}

isContainerExist
[ $? -ne 1 ] && {
	echo 2
	exit 2
}

isContainerRunning
if [ $? -eq 1 ]; then
	echo 0
	exit 0
else
	echo 3
	exit 3
fi