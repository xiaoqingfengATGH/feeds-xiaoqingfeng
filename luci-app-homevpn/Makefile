# SPDX-License-Identifier: MIT
# luci-app-homevpn — turnkey strongSwan IKEv2 VPN server for HomeLede.
# Based on luci-app-ikev2-manager (C) naughtyGitCat, MIT.
include $(TOPDIR)/rules.mk

LUCI_TITLE:=Turnkey strongSwan IKEv2 VPN server (EAP users, certs, provisioning)
LUCI_DESCRIPTION:=Provisions a router-local strongSwan IKEv2 EAP-MSCHAPv2 server on first boot: \
	swanctl connection DHCP-pool client addressing + farp, self-signed PKI, \
	INPUT firewall rules for 500/4500/ESP, EAP user management and iOS/Android \
	client profiles. Certificate modes: self-signed / import / ACME sync.
LUCI_DEPENDS:=+strongswan-swanctl +strongswan-mod-eap-mschapv2 +strongswan-mod-gcm \
	+strongswan-mod-openssl +strongswan-mod-curve25519 +strongswan-mod-pkcs8 \
	+strongswan-mod-dhcp +strongswan-mod-farp +openssl-util
LUCI_PKGARCH:=all
PKG_VERSION:=2.0.0
PKG_RELEASE:=1
PKG_LICENSE:=MIT
PKG_MAINTAINER:=xiaoqingfeng <xiaoqingfengatgm@gmail.com>

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
