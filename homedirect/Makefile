include $(TOPDIR)/rules.mk

PKG_NAME:=homedirect
PKG_VERSION:=0.1.0
PKG_RELEASE:=1
PKG_LICENSE:=Apache-2.0
PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)-$(PKG_VERSION)

include $(INCLUDE_DIR)/package.mk

define Package/homedirect
  SECTION:=net
  CATEGORY:=Network
  TITLE:=Bounded independent HomeDirect HTTPS service
  DEPENDS:=+libgcc +lua +libuci-lua +nginx-ssl +natmap +curl +ca-bundle
endef

define Package/homedirect/conffiles
/etc/config/homedirect
endef

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
	$(CP) ./src/lease-supervisor.c ./src/publisher.c $(PKG_BUILD_DIR)/
endef

define Build/Compile
	$(TARGET_CC) $(TARGET_CPPFLAGS) $(TARGET_CFLAGS) -Wall -Wextra -Werror -o $(PKG_BUILD_DIR)/homedirect-publish $(PKG_BUILD_DIR)/publisher.c $(TARGET_LDFLAGS)
	$(TARGET_CC) $(TARGET_CPPFLAGS) $(TARGET_CFLAGS) -Wall -Wextra -Werror -o $(PKG_BUILD_DIR)/homedirect-lease $(PKG_BUILD_DIR)/lease-supervisor.c $(TARGET_LDFLAGS)
endef

define Package/homedirect/install
	$(INSTALL_DIR) $(1)/usr/libexec $(1)/usr/share/homedirect $(1)/etc/config $(1)/etc/init.d $(1)/etc/homedirect
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/homedirect-lease $(1)/usr/libexec/homedirect-lease
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/homedirect-publish $(1)/usr/libexec/homedirect-publish
	$(INSTALL_DATA) ./files/usr/share/homedirect/*.lua $(1)/usr/share/homedirect/
	$(INSTALL_BIN) ./files/usr/share/homedirect/lease-run.sh $(1)/usr/share/homedirect/
	$(INSTALL_CONF) ./files/etc/config/homedirect $(1)/etc/config/homedirect
	$(INSTALL_BIN) ./files/etc/init.d/homedirect $(1)/etc/init.d/homedirect
	chmod 0700 $(1)/etc/homedirect
endef

$(eval $(call BuildPackage,homedirect))
