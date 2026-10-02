# SPDX-License-Identifier: MIT
# luci-app-ikev2-manager — manage strongSwan IKEv2 EAP users from LuCI.
# Build inside an OpenWrt/LuCI feed tree, or copy ./root and ./htdocs onto the router.
include $(TOPDIR)/rules.mk
LUCI_TITLE:=LuCI app to manage strongSwan IKEv2 EAP users + iOS/macOS profiles
LUCI_DEPENDS:=+strongswan-swanctl +strongswan-mod-eap-mschapv2 +openssl-util
LUCI_PKGARCH:=all
PKG_VERSION:=1.0.0
PKG_RELEASE:=3
PKG_LICENSE:=MIT
PKG_MAINTAINER:=psyduck
include $(TOPDIR)/feeds/luci/luci.mk
# call BuildPackage - OpenWrt buildroot signature
