# Makefile to create p7zip for LEDE/OpenWRT
#
# Copyright (C) 2017- Darcy Hu <hot123tea123@gmail.com>
#
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=p7zip
PKG_VERSION:=16.02
PKG_RELEASE:=1

http://sourceforge.net/projects/p7zip/files/p7zip/$(PKG_VERSION)/p7zip_$(PKG_VERSION)_src_all.tar.bz2/download

PKG_SOURCE:=$(PKG_NAME)_$(PKG_VERSION)_src_all.tar.bz2
PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)_$(PKG_VERSION)
PKG_SOURCE_URL:=@SF/$(PKG_NAME)/$(PKG_NAME)/$(PKG_VERSION)
PKG_MD5SUM:=a0128d661cfe7cc8c121e73519c54fbf

include $(INCLUDE_DIR)/package.mk

define Package/p7zip
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=p7zip archiver
  URL:=http://http://www.7-zip.org
  DEPENDS:=+libstdcpp
endef

MAKE_FLAGS += 7z

define Package/p7zip/install
	$(INSTALL_DIR) $(1)/usr/lib/
	$(CP) -r $(PKG_BUILD_DIR)/bin/ $(1)/usr/lib/p7zip

	$(INSTALL_DIR) $(1)/usr/bin/
	$(INSTALL_BIN) ./files/7z $(1)/usr/bin
endef

$(eval $(call BuildPackage,p7zip))

