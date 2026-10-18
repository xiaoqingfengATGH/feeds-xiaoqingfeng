# SPDX-License-Identifier: MIT
# luci-app-homevpn — turnkey strongSwan IKEv2 VPN server for HomeLede.
# Based on luci-app-ikev2-manager (C) naughtyGitCat, MIT.
include $(TOPDIR)/rules.mk

# jsmin strips the leading 'require ...'; pragma lines — LuCI's module loader
# then can't inject view/rpc/ui/E globals and every button on the page dies.
LUCI_MINIFY_JS:=0

LUCI_TITLE:=HomeVPN
LUCI_DESCRIPTION:=Homelede customized IKEv2 + EAP-MSCHAPv2 VPN server, supporting the default clients on iOS, Android, Windows and MacOS for convenient device access to your home network.
LUCI_DEPENDS:=+strongswan-swanctl +strongswan-mod-eap-mschapv2 +strongswan-mod-gcm \
	+strongswan-mod-openssl +strongswan-mod-curve25519 +strongswan-mod-pkcs8 \
	+strongswan-mod-dhcp +strongswan-mod-farp +openssl-util +libopenssl-legacy \
	+iputils-arping
LUCI_PKGARCH:=all
PKG_VERSION:=2.1.0
PKG_RELEASE:=31
# Keep the translation package upgradeable before its first git revision.
PKG_PO_VERSION:=$(PKG_VERSION)-r$(PKG_RELEASE)
PKG_LICENSE:=MIT
PKG_MAINTAINER:=xiaoqingfeng <xiaoqingfengatgm@gmail.com>
# luci.mk calls this package-specific hook after copying root/* into the
# build directory, then preserves its mode with cp -pR during installation.
# Do not use PKG_FILE_MODES: it also applies to probe-free translation IPKs.
define Build/Prepare/luci-app-homevpn
	$(INSTALL_BIN) ./root/etc/homestatus-probes/homevpn $(PKG_BUILD_DIR)/root/etc/homestatus-probes/homevpn
endef

# /etc/config/homevpn ships as a package file but is NOT a conffile by
# default — without this marker opkg --force-reinstall / upgrades happily
# OVERWRITE user config (EAP users, fixed IPs, cert mode, remote) with the
# package defaults. Declare it a conffile so upgrades preserve it.
define Package/luci-app-homevpn/conffiles
/etc/config/homevpn
endef

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
