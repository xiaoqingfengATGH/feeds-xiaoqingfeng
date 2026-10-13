include $(TOPDIR)/rules.mk

PKG_NAME:=homestun
PKG_VERSION:=0.1.0
PKG_RELEASE:=1
PKG_LICENSE:=Apache-2.0
PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)-$(PKG_VERSION)

include $(INCLUDE_DIR)/package.mk

define Package/homestun
  SECTION:=net
  CATEGORY:=Network
  TITLE:=Bounded independent HomeSTUN HTTPS service
  DEPENDS:=+libgcc +lua +libuci-lua +nginx-ssl +natmap +curl +ca-bundle
endef

define Package/homestun/conffiles
/etc/config/homestun
endef

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
	$(CP) ./src/lease-supervisor.c ./src/publisher.c $(PKG_BUILD_DIR)/
endef

define Build/Compile
	$(TARGET_CC) $(TARGET_CPPFLAGS) $(TARGET_CFLAGS) -Wall -Wextra -Werror -o $(PKG_BUILD_DIR)/homestun-publish $(PKG_BUILD_DIR)/publisher.c $(TARGET_LDFLAGS)
	$(TARGET_CC) $(TARGET_CPPFLAGS) $(TARGET_CFLAGS) -Wall -Wextra -Werror -o $(PKG_BUILD_DIR)/homestun-lease $(PKG_BUILD_DIR)/lease-supervisor.c $(TARGET_LDFLAGS)
endef

define Package/homestun/install
	$(INSTALL_DIR) $(1)/usr/libexec $(1)/usr/share/homestun $(1)/etc/config $(1)/etc/init.d $(1)/etc/homestun
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/homestun-lease $(1)/usr/libexec/homestun-lease
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/homestun-publish $(1)/usr/libexec/homestun-publish
	$(INSTALL_DATA) ./files/usr/share/homestun/*.lua $(1)/usr/share/homestun/
	$(INSTALL_BIN) ./files/usr/share/homestun/lease-run.sh $(1)/usr/share/homestun/
	$(INSTALL_CONF) ./files/etc/config/homestun $(1)/etc/config/homestun
	$(INSTALL_BIN) ./files/etc/init.d/homestun $(1)/etc/init.d/homestun
	chmod 0700 $(1)/etc/homestun
endef

$(eval $(call BuildPackage,homestun))
