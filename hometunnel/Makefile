# SPDX-License-Identifier: Apache-2.0
#
# Copyright (C) 2026 xiaoqingfeng <xiaoqingfengatgm@gmail.com>
#
# hometunnel — HomeLede 定制的全免费 Cloudflare Tunnel 内网穿透
# 灵感与控制面协议来源: https://github.com/AI-X-Space/llm-ondemand-tunnel (Apache-2.0)

include $(TOPDIR)/rules.mk

PKG_NAME:=hometunnel
PKG_VERSION:=1.0.0
PKG_RELEASE:=1
PKG_LICENSE:=Apache-2.0
PKG_MAINTAINER:=xiaoqingfeng <xiaoqingfengatgm@gmail.com>

include $(INCLUDE_DIR)/package.mk

define Package/hometunnel
  SECTION:=net
  CATEGORY:=Network
  SUBMENU:=Web Servers/Proxies
  TITLE:=HomeLede Cloudflare Tunnel manager
  URL:=https://github.com/xiaoqingfengATGH/feeds-xiaoqingfeng
  DEPENDS:=+cloudflared +curl +ca-bundle
endef

define Package/hometunnel/description
 HomeLede-tailored intranet exposure via Cloudflare Tunnel (fully free tier).
 Requires only a Cloudflare account and a domain hosted on Cloudflare.
 Two modes:
   ondemand — tunnel is started/stopped from outside via a Cloudflare Worker
              control plane (TTL + auto-renew on traffic + fail-closed),
              inspired by AI-X-Space/llm-ondemand-tunnel.
   alwayson — tunnel always connected at boot.
 Ingress rules are managed via UCI and rendered to a locally-managed
 cloudflared config.yml.
endef

define Package/hometunnel/conffiles
/etc/config/hometunnel
endef

define Build/Compile
endef

define Package/hometunnel/install
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./files/etc/config/hometunnel $(1)/etc/config/hometunnel
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/etc/init.d/hometunnel $(1)/etc/init.d/hometunnel
	$(INSTALL_BIN) ./files/etc/init.d/hometunnel-ctl $(1)/etc/init.d/hometunnel-ctl
	$(INSTALL_DIR) $(1)/etc/uci-defaults
	$(INSTALL_BIN) ./files/etc/uci-defaults/99-hometunnel $(1)/etc/uci-defaults/99-hometunnel
	$(INSTALL_DIR) $(1)/usr/share/hometunnel/worker
	$(INSTALL_BIN) ./files/usr/share/hometunnel/hometunnel.sh $(1)/usr/share/hometunnel/hometunnel.sh
	$(INSTALL_BIN) ./files/usr/share/hometunnel/gen-yml.sh $(1)/usr/share/hometunnel/gen-yml.sh
	$(INSTALL_BIN) ./files/usr/share/hometunnel/ctl-loop.sh $(1)/usr/share/hometunnel/ctl-loop.sh
	$(INSTALL_DATA) ./files/usr/share/hometunnel/worker/worker.js.tpl $(1)/usr/share/hometunnel/worker/worker.js.tpl
	$(INSTALL_DATA) ./files/usr/share/hometunnel/worker/wrangler.toml.tpl $(1)/usr/share/hometunnel/worker/wrangler.toml.tpl
	$(INSTALL_DATA) ./files/usr/share/hometunnel/worker/deploy.sh.tpl $(1)/usr/share/hometunnel/worker/deploy.sh.tpl
	$(INSTALL_DATA) ./files/usr/share/hometunnel/worker/README.txt.tpl $(1)/usr/share/hometunnel/worker/README.txt.tpl
endef

$(eval $(call BuildPackage,hometunnel))
