#!/bin/bash
set -e

LIST_FILE_PREFIX="chnlist_"

source dnslist.sh
source conflist.sh

./downloadConf.sh
./refreshConf.sh
./flush.sh
