#!/bin/sh
BASE_FOLDER=/etc/beamInDocker

DOCKER_IMAGE_ID="$(uci -q get beamInDocker.beam.imageid)"
BEAM_VERSION="$(uci -q get beamInDocker.beam.version)"
DOCKER_IMAGE_URL="$(uci -q get beamInDocker.beam.imageurl)"
DOCKER_IMAGE_MD5="$(uci -q get beamInDocker.beam.imagepkgmd5)"
BEAM_GUI_PORT="$(uci -q get beamInDocker.beam.guiport)"

DOCKER_CONTAINER_NAME="xqf999_beam"

DOCKER_NET_NAME=beam-net
DOCKER_NET_ADDRESS=172.31.255.0/24
DOCKER_NET_GATEWAY=172.31.255.1
BEAM_IP=172.31.255.254
BEAM_DNS=1.1.1.1

function isImageExist()
{
	local xx=$(docker images | grep $DOCKER_IMAGE_ID | wc -l)
	return $xx
}
#isImageExist
#[ $? -eq 1 ] && echo "Image Exist"

function isContainerExist()
{
	local yy=$(docker ps -a | grep $DOCKER_CONTAINER_NAME | grep $DOCKER_IMAGE_ID | wc -l)
	return $yy
}
#isContainerExist
#[ $? -eq 1 ] && echo "Container Exist"

function isContainerRunning()
{
	local zz=$(docker ps -q --filter name=^/$DOCKER_CONTAINER_NAME$ --filter status=running --filter status=restarting | wc -l)
	return $zz
}
#isContainerRunning
#[ $? -eq 1 ] && echo "isContainerRunning"

CURRENT_CONTAINERID=""
function getContainerId()
{
	local ww=$(docker ps -q -a --filter name=^/$DOCKER_CONTAINER_NAME$)
	CURRENT_CONTAINERID=$ww;
}

function isNetworkExist()
{
	local ww=$(docker network ls | grep $DOCKER_NET_NAME | wc -l)
	return $ww
}

function createNetwork()
{
	docker network create -d bridge --gateway=$DOCKER_NET_GATEWAY --subnet=$DOCKER_NET_ADDRESS $DOCKER_NET_NAME
}

function removeNetwork()
{
	 docker network rm $DOCKER_NET_NAME
}

###################### Public Functions ######################

function startContainer()
{
	isImageExist
	[ $? -eq 0 ] && {
		[ -f /etc/beamInDocker/preLoad.7z ] && {
			7z x -so /etc/beamInDocker/preLoad.7z |docker load
		} || {
			return 1
		}
	}
	isContainerRunning
	[ $? -eq 1 ] && return 2
	isContainerExist
	[ $? -eq 0 ] && {
		isNetworkExist
		if [ $? -eq 0 ]; then
			createNetwork
		fi
		docker run -d --name $DOCKER_CONTAINER_NAME --network=$DOCKER_NET_NAME --ip $BEAM_IP --dns $BEAM_DNS -p $BEAM_GUI_PORT:8080/tcp $DOCKER_IMAGE_ID
		return $?
	} || {
		getContainerId
		docker start $CURRENT_CONTAINERID
		return $?
	}
}

function stopContainer()
{
	isImageExist
	[ $? -eq 0 ] && return 1
	isContainerRunning
	[ $? -ne 1 ] && return 2
	getContainerId
	docker stop $CURRENT_CONTAINERID
	local stopResult=$?
	#removeNetwork
	return $stopResult
}

function clearContainer()
{
	isImageExist
	[ $? -eq 0 ] && return 0
	isContainerRunning
	if [ $? -eq 1 ]; then
		stopContainer
	fi
	docker rm $(docker ps -q --filter name=^/$DOCKER_CONTAINER_NAME$ --filter status=exited --filter status=dead 2>/dev/null)
}
