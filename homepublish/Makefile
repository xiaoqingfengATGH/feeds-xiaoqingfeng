include $(TOPDIR)/rules.mk

PKG_NAME:=homepublish
PKG_VERSION:=0.1.0
PKG_RELEASE:=8
PKG_LICENSE:=Apache-2.0
PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)-$(PKG_VERSION)

include $(INCLUDE_DIR)/package.mk

define Package/homepublish
  SECTION:=net
  CATEGORY:=Network
  TITLE:=Bounded independent HomePublish HTTPS service
  DEPENDS:=+libgcc +liblua +lua +libuci-lua +nginx-ssl +luci-lib-nixio +curl +ca-bundle
endef

define Package/homepublish/conffiles
/etc/config/homepublish
endef

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
	$(CP) ./src/product-store.c $(PKG_BUILD_DIR)/
endef

define Build/Compile
	$(TARGET_CC) $(TARGET_CPPFLAGS) $(TARGET_CFLAGS) -std=c99 -Wall -Wextra -Werror -fPIC -shared -I$(STAGING_DIR)/usr/include -o $(PKG_BUILD_DIR)/homepublish_store.so $(PKG_BUILD_DIR)/product-store.c $(TARGET_LDFLAGS) -llua
endef

define Package/homepublish/install
	$(INSTALL_DIR) $(1)/usr/libexec $(1)/usr/lib/lua $(1)/usr/share/homepublish $(1)/etc/config $(1)/etc/init.d $(1)/etc/homepublish
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/homepublish_store.so $(1)/usr/lib/lua/homepublish_store.so
	$(INSTALL_DATA) ./files/usr/share/homepublish/*.lua $(1)/usr/share/homepublish/
	$(INSTALL_CONF) ./files/etc/config/homepublish $(1)/etc/config/homepublish
	$(INSTALL_BIN) ./files/etc/init.d/homepublish* $(1)/etc/init.d/
	chmod 0700 $(1)/etc/homepublish
endef

$(eval $(call BuildPackage,homepublish))
