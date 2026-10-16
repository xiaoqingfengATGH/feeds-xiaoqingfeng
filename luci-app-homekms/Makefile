include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-homekms
PKG_VERSION:=1.0.0
PKG_RELEASE:=1
PKG_LICENSE:=Apache-2.0

LUCI_TITLE:=HomeKMS service configuration
LUCI_DEPENDS:=+luci-base +homekms
LUCI_PKGARCH:=all

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
