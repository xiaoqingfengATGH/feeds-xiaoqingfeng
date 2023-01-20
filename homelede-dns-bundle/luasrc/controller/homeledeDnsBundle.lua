-- Copyright 2023 Richard <xiaoqingfengatgm@gmail.com>
-- feed site : https://github.com/xiaoqingfengATGH/feeds-xiaoqingfeng
module("luci.controller.homeledeDnsBundle", package.seeall)
local appname = "homeledeDnsBundle"
local RUNLOG_DIR = "/tmp/hr"
local ucic = luci.model.uci.cursor()
local http = require "luci.http"

function index()
	
	entry({"admin", "dns", "homeledeDnsBundle", "show"}, call("show_menu")).leaf = true
    entry({"admin", "dns", "homeledeDnsBundle", "hide"}, call("hide_menu")).leaf = true
	
    if nixio.fs.access("/etc/config/homeledeDnsBundle") and
        nixio.fs.access("/etc/config/homeledeDnsBundle_show") then
            entry({"admin", "dns", "homeledeDnsBundle"},
			alias("admin", "dns", "homeledeDnsBundle", "settings"),
			_("Homelede Dns Control Panel"), 10).dependent = true
    end
	
    entry({"admin", "dns", "homeledeDnsBundle", "settings"},
          cbi("homeledeDnsBundle/settings")).leaf = true
    entry({"admin", "dns", "homeledeDnsBundle", "status"}, call("status")).leaf =
        true
end

local function http_write_json(content)
	http.prepare_content("application/json")
	http.write_json(content or {code = 1})
end

function status()
	local statusJson = luci.sys.exec("/etc/homeledeDnsBundle/bundleStatus.sh")
	http.prepare_content("application/json")
    http.write(statusJson)
end

function show_menu()
    luci.sys.call("touch /etc/config/homeledeDnsBundle_show")
    luci.http.redirect(luci.dispatcher.build_url("admin", "dns", "homeledeDnsBundle"))
end

function hide_menu()
    luci.sys.call("rm -rf /etc/config/homeledeDnsBundle_show")
    luci.http.redirect(luci.dispatcher.build_url("admin", "status", "overview"))
end

