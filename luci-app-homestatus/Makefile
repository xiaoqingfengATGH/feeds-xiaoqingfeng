#
# Copyright (C) 2026 xiaoqingfeng <xiaoqingfengatgm@gmail.com>
#
# This is free software, licensed under the Apache License, Version 2.0 .
#

include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-homestatus
PKG_VERSION:=1.0.0
PKG_RELEASE:=1

PKG_LICENSE:=Apache-2.0
PKG_MAINTAINER:=xiaoqingfeng <xiaoqingfengatgm@gmail.com>
PKGARCH:=all

LUCI_TITLE:=LuCI app for HomeLede overview extensions
LUCI_DESCRIPTION:=Adds two configurable overview-page cards to HomeLede: disk capacity \
 (disk -> partition -> mount point tree) and key application status monitoring, with \
 per-app service restart.
LUCI_DEPENDS:=+rpcd-mod-ucode +ucode +ucode-mod-fs +ucode-mod-ubus

define Package/$(PKG_NAME)/conffiles
/etc/config/homestatus
endef

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
