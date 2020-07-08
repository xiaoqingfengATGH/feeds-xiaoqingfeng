#!/bin/sh
INSTALL_LOC=/etc/dnsmasq-china-list

CONF_DIR=$INSTALL_LOC/template/

TMP_FOLDER=/tmp/dnsmasq-china-list
[ -d $TMP_FOLDER ] && rm -rf $TMP_FOLDER
mkdir -p $TMP_FOLDER

CURRENT_VERSION_FILE=$CONF_DIR""version

wget https://gitee.com/xiaoqingfeng999/dnsmasq-china-list-pkgs/raw/master/version -O $TMP_FOLDER/version

DOWNLOAD_VER=$(cat $TMP_FOLDER/version | awk -F' ' '{print $2}')
CURRENT_VER="NA"
[ -r $CURRENT_VERSION_FILE ] && CURRENT_VER=$(cat $CURRENT_VERSION_FILE | awk -F' ' '{print $2}')

if [ "$CURRENT_VER" = "$DOWNLOAD_VER" ]; then
	echo "The current version is already the latest version."
	exit 0
fi

echo "New updates available."

$INSTALL_LOC/downloadConf.sh

cp $TMP_FOLDER/version $CURRENT_VERSION_FILE
echo Version mark has been updated.

$INSTALL_LOC/refreshConf.sh
$INSTALL_LOC/flush.sh
echo dnsmasq_china_list updated.
