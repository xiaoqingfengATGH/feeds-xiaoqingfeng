include $(TOPDIR)/rules.mk
PKG_NAME:=homepublish-engines
PKG_VERSION:=1.30.6
PKG_RELEASE:=1
PKG_LICENSE:=BSD-2-Clause GPL-3.0-or-later LGPL-2.1-or-later LGPL-3.0-or-later
PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)-$(PKG_VERSION)
# sslh v2.3.1 = d39388d1edcc9fe7a35449fc5c23d222d20d6f81
PKG_BUILD_DEPENDS:=openssl pcre2 zlib libcap
include $(INCLUDE_DIR)/package.mk

define Download/hp-nginx
  FILE:=nginx-1.30.6.tar.gz
  URL:=https://nginx.org/download
  HASH:=3cf46f5ed7504d460125866b7bea99fb357f31d887e2e63b35503310e9b8b6c8
endef
define Download/hp-sslh
  FILE:=sslh-d39388d1.tar.gz
  URL:=https://codeload.github.com/yrutschle/sslh/tar.gz
  URL_FILE:=d39388d1edcc9fe7a35449fc5c23d222d20d6f81
  HASH:=4822815217ba8c19d8a7469d19e686a5a3f6a0388e772636996f9cae1cdbc056
endef
define Download/hp-proxy
  FILE:=libproxyprotocol-3e133b96.tar.gz
  URL:=https://codeload.github.com/kosmas-valianos/libproxyprotocol/tar.gz
  URL_FILE:=3e133b9602e59f47ceceef74fbd52a3b147e5874
  HASH:=ecfaa002f2f36a87c7e52f515a6caaec492fb69ed5f0f74295934ed3b8475882
endef
define Download/hp-config
  FILE:=libconfig-1.7.3.tar.gz
  URL:=https://hyperrealm.github.io/libconfig/dist
  HASH:=545166d6cac037744381d1e9cc5a5405094e7bfad16a411699bcff40bbb31ee7
endef
$(eval $(call Download,hp-nginx))
$(eval $(call Download,hp-sslh))
$(eval $(call Download,hp-proxy))
$(eval $(call Download,hp-config))

define Package/homepublish-engines
  SECTION:=net
  CATEGORY:=Network
  TITLE:=HomePublish private Nginx and sslh 2.3.1 engines
  DEPENDS:=@TARGET_x86_64 +libc +libgcc +libopenssl +libpcre2 +zlib +libcap
endef

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)/sources
	$(CP) $(DL_DIR)/nginx-1.30.6.tar.gz $(DL_DIR)/sslh-d39388d1.tar.gz $(DL_DIR)/libproxyprotocol-3e133b96.tar.gz $(DL_DIR)/libconfig-1.7.3.tar.gz $(PKG_BUILD_DIR)/sources/
	$(CP) ./build-components.sh $(PKG_BUILD_DIR)/
endef

define Build/Compile
	sh $(PKG_BUILD_DIR)/build-components.sh $(TOPDIR) $(PKG_BUILD_DIR)/build $(PKG_BUILD_DIR)/sources
endef

define Package/homepublish-engines/install
	$(INSTALL_DIR) $(1)/usr/libexec/homepublish $(1)/usr/share/homepublish/licenses
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/build/out/nginx $(1)/usr/libexec/homepublish/nginx
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/build/out/sslh-select $(1)/usr/libexec/homepublish/sslh-select
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/build/nginx-1.30.6/LICENSE $(1)/usr/share/homepublish/licenses/nginx-LICENSE
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/build/sslh-d39388d1edcc9fe7a35449fc5c23d222d20d6f81/COPYING $(1)/usr/share/homepublish/licenses/sslh-COPYING
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/build/libconfig-1.7.3/COPYING.LIB $(1)/usr/share/homepublish/licenses/libconfig-COPYING.LIB
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/build/libproxyprotocol-3e133b9602e59f47ceceef74fbd52a3b147e5874/COPYING* $(1)/usr/share/homepublish/licenses/
endef
$(eval $(call BuildPackage,homepublish-engines))
