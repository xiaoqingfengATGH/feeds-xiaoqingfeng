#
# Copyright (c) 2018-2020 xiaoqingfeng (xiaoqingfengatgm@gmail.com)
# This is free software, licensed under the GNU General Public License v3.
#
include $(TOPDIR)/rules.mk

PKG_NAME:=homelede-autoconfig
PKG_VERSION:=1.0
PKG_RELEASE:=1
PKG_DATE:=20200401
PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)

PKG_MAINTAINER:=xiaoqingfeng <xiaoqingfengatgm@gmail.com>
PKG_LICENSE:=GPL-3.0-or-later
PKG_LICENSE_FILES:=LICENSE

include $(INCLUDE_DIR)/package.mk

define Package/$(PKG_NAME)
  TITLE:=Auto config scripts for HomeLede
  DEPENDS:=@TARGET_x86
endef

define Package/$(PKG_NAME)/config
help
	$(PKG_NAME)
	Version: $(PKG_VERSION)-$(PKG_RELEASE)
	Provide base files and base configurations for HomeLede.
endef

define Package/$(PKG_NAME)/description
Provide base files and base configurations for HomeLede.
endef

define Package/$(PKG_NAME)/install
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) files/etc/init.d/homelede-autoconfig $(1)/etc/init.d
	$(INSTALL_DATA) files/etc/brand $(1)/etc
endef

define Package/$(PKG_NAME)/postinst
#!/bin/sh
exit 0
endef

define Package/$(PKG_NAME)/prerm
#!/bin/sh
exit 0
endef

define Build/Configure
endef

define Build/Prepare
endef

define Build/Compile
endef

$(eval $(call BuildPackage,$(PKG_NAME)))
