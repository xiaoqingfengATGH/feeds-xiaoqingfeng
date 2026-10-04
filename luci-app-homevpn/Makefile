# SPDX-License-Identifier: MIT
# luci-app-homevpn — turnkey strongSwan IKEv2 VPN server for HomeLede.
# Based on luci-app-ikev2-manager (C) naughtyGitCat, MIT.
include $(TOPDIR)/rules.mk

# jsmin strips the leading 'require ...'; pragma lines — LuCI's module loader
# then can't inject view/rpc/ui/E globals and every button on the page dies.
LUCI_MINIFY_JS:=0

LUCI_TITLE:=Turnkey strongSwan IKEv2 VPN server (EAP users, certs, provisioning)
LUCI_DESCRIPTION:=Provisions a router-local strongSwan IKEv2 EAP-MSCHAPv2 server on first boot: \
	swanctl connection DHCP-pool client addressing + farp, self-signed PKI, \
	INPUT firewall rules for 500/4500/ESP, EAP user management and iOS/Android \
	client profiles. Certificate modes: self-signed / import / ACME sync.
LUCI_DEPENDS:=+strongswan-swanctl +strongswan-mod-eap-mschapv2 +strongswan-mod-gcm \
	+strongswan-mod-openssl +strongswan-mod-curve25519 +strongswan-mod-pkcs8 \
	+strongswan-mod-dhcp +strongswan-mod-farp +openssl-util +libopenssl-legacy \
	+iputils-arping
LUCI_PKGARCH:=all
PKG_VERSION:=2.1.0
PKG_RELEASE:=20
PKG_LICENSE:=MIT
PKG_MAINTAINER:=xiaoqingfeng <xiaoqingfengatgm@gmail.com>

# /etc/config/homevpn ships as a package file but is NOT a conffile by
# default — without this marker opkg --force-reinstall / upgrades happily
# OVERWRITE user config (EAP users, fixed IPs, cert mode, remote) with the
# package defaults. Declare it a conffile so upgrades preserve it.
define Package/luci-app-homevpn/conffiles
/etc/config/homevpn
endef

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
