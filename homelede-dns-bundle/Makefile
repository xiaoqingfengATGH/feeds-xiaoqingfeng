# Copyright (C) 2023 xiaoqingfeng <xiaoqingfengatgm@gmail.com>
#
# This is free software, licensed under the Apache License, Version 2.0 .
#

include $(TOPDIR)/rules.mk

LUCI_TITLE:=HomeledeDnsBundle
LUCI_DEPENDS:=+AdGuardHome +chinadns-ng +dnscrypt-proxy2 +smartdns +dnsmasq-full
LUCI_PKGARCH:=all
PKG_NAME:=luci-app-HomeledeDnsBundle
PKG_VERSION:=1.0
PKG_RELEASE:=1-20230120
PKG_MAINTAINER:=Richard Yu <xiaoqingfengatgm@gmail.com>

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
