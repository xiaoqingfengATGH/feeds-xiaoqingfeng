-- Copyright 2020 Richard <xiaoqingfengatgm@gmail.com>
-- feed site : https://github.com/xiaoqingfengATGH/feeds-xiaoqingfeng
module("luci.controller.homeredirect", package.seeall)

function index()
	
	entry({"admin", "services", "homeredirect", "show"}, call("show_menu")).leaf = true
    entry({"admin", "services", "homeredirect", "hide"}, call("hide_menu")).leaf = true
	
    if nixio.fs.access("/etc/config/homeredirect") and
        nixio.fs.access("/etc/config/homeredirect_show") then
            entry({"admin", "services", "homeredirect"},
			alias("admin", "services", "homeredirect", "settings"),
			_("Home Redirect"), 50).dependent = false
    end
	
    entry({"admin", "services", "homeredirect", "settings"},
          cbi("homeredirect/settings"), _("General Settings"), 10).leaf = true
    entry({"admin", "services", "homeredirect", "status"}, call("status")).leaf =
        true
end

function status()
    local e = {}
    e.status = tonumber(luci.sys.exec("/usr/share/homeredirect/getContainerState.sh"))
    luci.http.prepare_content("application/json")
    luci.http.write_json(e)
end

function show_menu()
    luci.sys.call("touch /etc/config/homeredirect_show")
    luci.http.redirect(luci.dispatcher.build_url("admin", "services", "homeredirect"))
end

function hide_menu()
    luci.sys.call("rm -rf /etc/config/homeredirect_show")
    luci.http.redirect(luci.dispatcher.build_url("admin", "status", "overview"))
end

