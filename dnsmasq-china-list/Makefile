#
# Copyright (c) 2018-2020 xiaoqingfeng (xiaoqingfengatgm@gmail.com)
# This is free software, licensed under the GNU General Public License v3.
#
include $(TOPDIR)/rules.mk

PKG_NAME:=dnsmasq-china-list
PKG_VERSION:=1.0
PKG_RELEASE:=7
PKG_DATE:=20200921
PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)

PKG_MAINTAINER:=xiaoqingfeng <xiaoqingfengatgm@gmail.com>
PKG_LICENSE:=GPL-3.0-or-later
PKG_LICENSE_FILES:=LICENSE

include $(INCLUDE_DIR)/package.mk

define Package/$(PKG_NAME)
  SECTION:=net
  CATEGORY:=Network
  TITLE:=chinalist for dnsmasq
  DEPENDS:=+dnsmasq-full +bash +wget +p7zip
  PKGARCH:=all
  URL:=https://github.com/felixonmars/dnsmasq-china-list
endef

define Package/$(PKG_NAME)/description
Chinese-specific configuration to improve your favorite DNS server. Best partner for chnroutes.

Improve resolve speed for Chinese domains.

Get the best CDN node near you whenever possible, but don't compromise foreign CDN results so you also get best CDN node for your VPN at the same time.

Block ISP ads on NXDOMAIN result (like 114so).
endef

define Package/$(PKG_NAME)/install
	$(INSTALL_DIR) $(1)/etc/dnsmasq-china-list $(1)/etc/dnsmasq-china-list/template $(1)/etc/dnsmasq.d $(1)/etc/init.d
	$(INSTALL_BIN) files/etc/init.d/dnsmasq-china-list $(1)/etc/init.d
	$(INSTALL_BIN) files/etc/dnsmasq-china-list/install.sh $(1)/etc/dnsmasq-china-list
	$(INSTALL_BIN) files/etc/dnsmasq-china-list/clearConf.sh $(1)/etc/dnsmasq-china-list
	$(INSTALL_BIN) files/etc/dnsmasq-china-list/disable.sh $(1)/etc/dnsmasq-china-list
	$(INSTALL_BIN) files/etc/dnsmasq-china-list/downloadConf.sh $(1)/etc/dnsmasq-china-list
	$(INSTALL_BIN) files/etc/dnsmasq-china-list/flush.sh $(1)/etc/dnsmasq-china-list
	$(INSTALL_BIN) files/etc/dnsmasq-china-list/refreshConf.sh $(1)/etc/dnsmasq-china-list
	$(INSTALL_BIN) files/etc/dnsmasq-china-list/enable.sh $(1)/etc/dnsmasq-china-list
	$(INSTALL_BIN) files/etc/dnsmasq-china-list/update.sh $(1)/etc/dnsmasq-china-list
	$(INSTALL_CONF) files/etc/dnsmasq-china-list/conflist.sh $(1)/etc/dnsmasq-china-list
	$(INSTALL_CONF) files/etc/dnsmasq-china-list/dnslist.sh $(1)/etc/dnsmasq-china-list
	$(INSTALL_DATA) files/etc/dnsmasq-china-list/template/accelerated-domains.china.conf $(1)/etc/dnsmasq-china-list/template
	$(INSTALL_DATA) files/etc/dnsmasq-china-list/template/apple.china.conf $(1)/etc/dnsmasq-china-list/template
	$(INSTALL_DATA) files/etc/dnsmasq-china-list/template/google.china.conf $(1)/etc/dnsmasq-china-list/template
	$(INSTALL_DATA) files/etc/dnsmasq-china-list/template/bogus-nxdomain.china.conf $(1)/etc/dnsmasq-china-list/template
endef

define Package/$(PKG_NAME)/postinst
#!/bin/sh
/etc/init.d/dnsmasq-china-list enable
/etc/dnsmasq-china-list/enable.sh
exit 0
endef

define Package/$(PKG_NAME)/prerm
#!/bin/sh
/etc/dnsmasq-china-list/disable.sh
exit 0
endef

define Build/Configure
endef

define Build/Prepare
endef

define Build/Compile
$(CP) ./files/etc/dnsmasq-china-list/*.sh $(PKG_BUILD_DIR)
endef

$(eval $(call BuildPackage,$(PKG_NAME)))
