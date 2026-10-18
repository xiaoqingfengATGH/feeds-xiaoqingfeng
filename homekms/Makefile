include $(TOPDIR)/rules.mk

PKG_NAME:=homekms
PKG_VERSION:=1.0.0
PKG_RELEASE:=1
PKG_SOURCE_VERSION:=b0e1615dec06293c927625006a99e6ec54a001aa
PKG_SOURCE:=py-kms-$(PKG_SOURCE_VERSION).tar.gz
PKG_SOURCE_URL:=https://codeload.github.com/Py-KMS-Organization/py-kms/tar.gz/$(PKG_SOURCE_VERSION)?
PKG_HASH:=cc247a590141120f81b1fe591d42867ae428792cfc459236431e61d6f94ad89c
PKG_BUILD_DIR:=$(BUILD_DIR)/py-kms-$(PKG_SOURCE_VERSION)
PKG_LICENSE:=Unlicense
PKG_LICENSE_FILES:=LICENSE
PKGARCH:=all

include $(INCLUDE_DIR)/package.mk

define Package/homekms
  SECTION:=net
  CATEGORY:=Network
  TITLE:=HomeKMS volume-license protocol service
  DEPENDS:=+python3-light +python3-logging +python3-xml +python3-uuid +python3-multiprocessing +python3-ctypes +python3-sqlite3 +python3-pydoc +python3-unittest +firewall4 +rpcd
  USERID:=homekms:homekms
endef

define Package/homekms/conffiles
/etc/config/homekms
endef

define Build/Compile
endef

define Package/homekms/install
	$(INSTALL_DIR) $(1)/usr/share/homekms/pykms
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/py-kms/*.py $(1)/usr/share/homekms/pykms/
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/py-kms/KmsDataBase.xml $(1)/usr/share/homekms/pykms/
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/LICENSE $(1)/usr/share/homekms/LICENSE
	$(CP) ./files/* $(1)/
	chmod 0755 $(1)/etc/init.d/homekms $(1)/usr/libexec/rpcd/homekms $(1)/etc/homestatus-probes/homekms
endef

$(eval $(call BuildPackage,homekms))
