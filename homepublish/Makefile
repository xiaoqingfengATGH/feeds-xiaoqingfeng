include $(TOPDIR)/rules.mk

PKG_NAME:=homepublish
PKG_VERSION:=0.1.0
PKG_RELEASE:=9
PKG_LICENSE:=Apache-2.0
PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)-$(PKG_VERSION)

include $(INCLUDE_DIR)/package.mk

define Package/homepublish
  SECTION:=net
  CATEGORY:=Network
  TITLE:=Bounded independent HomePublish HTTPS service
  DEPENDS:=+libgcc +liblua +lua +libuci-lua +libubus-lua +homepublish-engines +luci-lib-nixio +curl +ca-bundle +openssl-util +firewall4 +nftables-json +luci-lib-jsonc +coreutils-timeout +flock
endef

define Package/homepublish/conffiles
/etc/config/homepublish
endef

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
endef

define Build/Compile
endef

define Package/homepublish/install
	$(INSTALL_DIR) $(1)/usr/libexec $(1)/usr/share/homepublish $(1)/etc/config $(1)/etc/init.d $(1)/etc/homepublish
	$(INSTALL_DATA) ./files/usr/share/homepublish/*.lua $(1)/usr/share/homepublish/
	$(INSTALL_DIR) $(1)/usr/share/nftables.d/table-post
	$(INSTALL_DATA) ./files/usr/share/nftables.d/table-post/90-homepublish.nft $(1)/usr/share/nftables.d/table-post/90-homepublish.nft
	$(INSTALL_CONF) ./files/etc/config/homepublish $(1)/etc/config/homepublish
	$(INSTALL_BIN) ./files/etc/init.d/homepublish* $(1)/etc/init.d/
	chmod 0700 $(1)/etc/homepublish
endef

$(eval $(call BuildPackage,homepublish))
