#
# Copyright (c) 2026 xiaoqingfeng (xiaoqingfengatgm@gmail.com)
# This is free software, licensed under the GNU General Public License v3.
#
# HomeLede trust anchors for the official OpenWrt release feeds.
#
# Why this package exists: HomeLede builds from an OpenWrt main-line tree
# whose openwrt-keyring only installs the snapshot usign key, while
# include/version.mk points distfeeds at an OpenWrt *release* (e.g.
# 24.10.5). Release Packages.sig files are signed with the release key,
# so without it `opkg update` fails with "Signature check failed".
#
# Kept separate from upstream openwrt-keyring (no fork drift on upstream
# sync) and from homelede-autoconfig (trust root must not live in a
# first-boot config script).
#
# The key is selected by VERSION_NUMBER. An unknown release fails the
# build on purpose: bumping version.mk without registering the matching
# release key here would otherwise silently break opkg on every device.
#
include $(TOPDIR)/rules.mk
include $(INCLUDE_DIR)/version.mk

PKG_NAME:=homelede-keyring
PKG_VERSION:=20261013
PKG_RELEASE:=1

PKG_MAINTAINER:=eric <xiaoqingfengatgm@gmail.com>
PKG_LICENSE:=GPL-2.0
# rebuild when the release series or package manager changes
PKG_CONFIG_DEPENDS:=CONFIG_VERSION_NUMBER CONFIG_USE_APK

include $(INCLUDE_DIR)/package.mk

# OpenWrt release series -> usign key id (files/usign/<keyid>, copied
# verbatim from https://git.openwrt.org/keyring.git usign/<keyid>).
HOMELEDE_KEY_24.10:=d310c6f2833e97f7

HOMELEDE_RELEASE_SERIES:=$(word 1,$(subst ., ,$(VERSION_NUMBER))).$(word 2,$(subst ., ,$(VERSION_NUMBER)))
HOMELEDE_KEY_ID:=$(HOMELEDE_KEY_$(HOMELEDE_RELEASE_SERIES))

define Package/$(PKG_NAME)
  SECTION:=base
  CATEGORY:=Base system
  TITLE:=HomeLede keyring for official OpenWrt release feeds
  PKGARCH:=all
endef

define Package/$(PKG_NAME)/description
  Installs the usign public key of the OpenWrt release series that
  HomeLede's distfeeds point to, so opkg can verify official package
  indexes.
endef

define Build/Prepare
endef

define Build/Configure
endef

# Guard runs at build time (not at Makefile parse time) so feed scanning
# and menuconfig keep working; only building this package fails.
define Build/Compile
	@if [ -n "$(CONFIG_USE_APK)" ]; then \
		echo "homelede-keyring: APK package manager is not supported yet; register the apk release key first" >&2; \
		exit 1; \
	fi
	@if [ -z "$(HOMELEDE_KEY_ID)" ]; then \
		echo "homelede-keyring: no usign key registered for VERSION_NUMBER=$(VERSION_NUMBER) (series $(HOMELEDE_RELEASE_SERIES)); add HOMELEDE_KEY_<series> and files/usign/<keyid>" >&2; \
		exit 1; \
	fi
	@[ -f ./files/usign/$(HOMELEDE_KEY_ID) ] || { \
		echo "homelede-keyring: missing files/usign/$(HOMELEDE_KEY_ID)" >&2; exit 1; }
endef

define Package/$(PKG_NAME)/install
	$(INSTALL_DIR) $(1)/etc/opkg/keys
	$(INSTALL_DATA) ./files/usign/$(HOMELEDE_KEY_ID) $(1)/etc/opkg/keys/$(HOMELEDE_KEY_ID)
endef

$(eval $(call BuildPackage,$(PKG_NAME)))
