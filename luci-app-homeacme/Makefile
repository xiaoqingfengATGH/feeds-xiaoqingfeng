#
# Copyright (C) 2010 OpenWrt.org
# Copyright (C) 2026 xiaoqingfeng
#
# This is free software, licensed under the GNU General Public License v3.
# See /LICENSE for more information.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-homeacme
PKG_VERSION:=1.0.0
PKG_RELEASE:=2
PKG_LICENSE:=GPL-3.0-or-later
PKG_MAINTAINER:=xiaoqingfeng
PKG_PO_VERSION:=$(PKG_VERSION)-r$(PKG_RELEASE)

LUCI_TITLE:=HomeLede ACME package - LuCI interface
LUCI_DEPENDS:=+acme +rpcd-mod-ucode +ucode-mod-fs +ucode-mod-uci +openssl-util +coreutils-timeout
LUCI_PKGARCH:=all
LUCI_MAINTAINER:=$(PKG_MAINTAINER)

# This tree's luci.mk has no LUCI_CONFLICTS hook. Extend package defaults
# locally, before luci.mk evaluates each generated package. The override
# survives package.mk reloading package-defaults.mk; no shared file changes.
# Keep acme.po / acme.*.lmo domains, but give translations homeacme names.
include $(INCLUDE_DIR)/package-defaults.mk

define HomeACME/SavePackageDefault
  define HomeACME/PackageDefault
$(value Package/Default)
  endef
endef
$(eval $(HomeACME/SavePackageDefault))

override define Package/Default
  $(HomeACME/PackageDefault)
  CONFLICTS:=$(subst homeacme,acme,$(1))
endef

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
