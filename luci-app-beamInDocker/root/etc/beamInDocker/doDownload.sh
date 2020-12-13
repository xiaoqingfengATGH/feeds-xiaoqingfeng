#!/bin/sh
. /etc/beamInDocker/dockerControl.sh
. /etc/beamInDocker/downloadCommon.sh

mkdir -p $TMP_FOLDER

echo $$ > $DOWNLOAD_PID

echo == D > $DOWNLOAD_PROGRESS

curl -SL $DOCKER_IMAGE_URL \
-o $DOWNLOAD_FILE >> $DOWNLOAD_PROGRESS 2>&1

echo == DS >> $DOWNLOAD_PROGRESS

echo == M >> $DOWNLOAD_PROGRESS
downloadedMd5=$(md5sum $DOWNLOAD_FILE | cut -d  ' ' -f 1)
if [ "$downloadedMd5" != "$DOCKER_IMAGE_MD5" ]; then
	echo 下载文件完整性校验失败! >> $DOWNLOAD_PROGRESS
	rm -f $DOWNLOAD_PID
	rm -rf $DOWNLOAD_FILE
	exit 1
fi
echo == MS >> $DOWNLOAD_PROGRESS

echo == U >> $DOWNLOAD_PROGRESS
7z x -so $DOWNLOAD_FILE 2>>$DOWNLOAD_PROGRESS |docker load >> $DOWNLOAD_PROGRESS 2>&1
if [ $? -ne 0 ]; then
	echo 解压并载入Docker镜像失败! >> $DOWNLOAD_PROGRESS
	rm -f $DOWNLOAD_PID
	exit 2
fi
echo == US >> $DOWNLOAD_PROGRESS

echo == I >> $DOWNLOAD_PROGRESS
docker tag $DOCKER_IMAGE_ID xiaoqingfeng999/beam:$BEAM_VERSION >> $DOWNLOAD_PROGRESS 2>&1
if [ $? -ne 0 ]; then
	echo Tag Docker镜像失败! >> $DOWNLOAD_PROGRESS
	rm -f $DOWNLOAD_PID
	exit 3
fi
echo == IS >> $DOWNLOAD_PROGRESS
rm -f $DOWNLOAD_PID
rm -rf $DOWNLOAD_FILE
