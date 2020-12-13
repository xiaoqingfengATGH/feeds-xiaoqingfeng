#!/bin/sh
TMP_UPDATE_INFO="/tmp/beamInDockerUpdateInfo"

UPDATE_INFO_URL=https://raw.githubusercontent.com/xiaoqingfengATGH/lantern/master/beam/latest

LATEST_VERSION="NA"
LATEST_IMAGEID="NA"
LATEST_TP_DOWNLOAD_URL="NA"
LATEST_TP_DOWNLOAD_MD5="NA"

function getLatestVersionInfo()
{
	curl -SL --connect-timeout 10 --max-time 20 $UPDATE_INFO_URL > $TMP_UPDATE_INFO
	if [ $? -ne 0 ]; then
		echo Get update info error!
		LATEST_VERSION="NA"
		LATEST_IMAGEID="NA"
		LATEST_TP_DOWNLOAD_URL="NA"
		LATEST_TP_DOWNLOAD_MD5="NA"
		return 1
	else
		echo Get update info finish!
		local update_info=$(cat $TMP_UPDATE_INFO)
		#local update_info="0.1.19 580a976cd4ac https://raw.githubusercontent.com/xiaoqingfengATGH/lantern/master/beam/beam.7z 07ab8b7b2b49c8516c7205ea1011d818"
		LATEST_VERSION=$(echo $update_info | cut -d' ' -f 1)
		LATEST_IMAGEID=$(echo $update_info | cut -d' ' -f 2)
		LATEST_TP_DOWNLOAD_URL=$(echo $update_info | cut -d' ' -f 3)
		LATEST_TP_DOWNLOAD_MD5=$(echo $update_info | cut -d' ' -f 4)
		
		echo LATEST_VERSION=$LATEST_VERSION
		echo LATEST_IMAGEID=$LATEST_IMAGEID
		echo LATEST_TP_DOWNLOAD_URL=$LATEST_TP_DOWNLOAD_URL
		echo LATEST_TP_DOWNLOAD_MD5=$LATEST_TP_DOWNLOAD_MD5
	fi
}

getLatestVersionInfo