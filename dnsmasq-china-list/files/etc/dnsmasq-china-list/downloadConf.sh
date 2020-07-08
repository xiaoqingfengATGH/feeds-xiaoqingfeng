#!/bin/bash
set -e

INSTALL_LOC=/etc/dnsmasq-china-list
source $INSTALL_LOC/conflist.sh

CONF_DIR=/etc/dnsmasq-china-list/template/

echo "Downloading latest configurations..."

#for _conf in "${CONF_WITH_SERVERS[@]}"; do
#        wget https://raw.fastgit.org/felixonmars/dnsmasq-china-list/master/$_conf.conf  -O $CONF_DIR$_conf.conf
#done
#for _conf in "${CONF_SIMPLE[@]}"; do
#        wget https://raw.fastgit.org/felixonmars/dnsmasq-china-list/master/$_conf.conf  -O $CONF_DIR$_conf.conf
#done

TMP_FOLDER=/tmp/dnsmasq-china-list
DOWNLOAD_VER=$(cat $TMP_FOLDER/version | awk -F' ' '{print $2}')

DOWNLOAD_SUCC=0
for i in 1 2 3; do
	wget https://gitee.com/xiaoqingfeng999/dnsmasq-china-list-pkgs/raw/master/configs.7z -O $TMP_FOLDER/configs.7z
	DOWNLOAD_PKG_MD5=$(md5sum $TMP_FOLDER/configs.7z | awk -F' ' '{print $1}')
	if [ "$DOWNLOAD_VER" = "$DOWNLOAD_PKG_MD5" ]; then
		DOWNLOAD_SUCC=1
		break
	fi
done

if [ "$DOWNLOAD_SUCC" = "0" ]; then
	echo "Download update failed!"
	exit 1
fi

rm -f $CONF_DIR""*.conf
7z e -o$CONF_DIR $TMP_FOLDER/configs.7z

echo "Download finished. All conf saved to "$CONF_DIR"."
