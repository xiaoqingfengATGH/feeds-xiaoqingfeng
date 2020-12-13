-- Copyright 2020 Richard <xiaoqingfengatgm@gmail.com>
module("luci.controller.beamInDocker", package.seeall)

function index()
    entry({"admin", "vpn"}, firstchild(), "VPN", 45).dependent = false
	
	entry({"admin", "vpn", "beamInDocker", "show"}, call("show_menu")).leaf = true
    entry({"admin", "vpn", "beamInDocker", "hide"}, call("hide_menu")).leaf = true
	
    if nixio.fs.access("/etc/config/beamInDocker") and
        nixio.fs.access("/etc/config/beamInDocker_show") then
            entry({"admin", "vpn", "beamInDocker"},
			alias("admin", "vpn", "beamInDocker", "settings"),
			_("Beam(Docker)"), 45).dependent = true
    end
	
    entry({"admin", "vpn", "beamInDocker", "settings"},
          cbi("beamInDocker/settings")).leaf = true
    
    entry({"admin", "vpn", "beamInDocker", "status"}, call("status")).leaf =
        true
	entry({"admin", "vpn", "beamInDocker", "downloadStatus"}, call("downloadStatus")).leaf =
        true
	entry({"admin", "vpn", "beamInDocker", "startDownload"}, call("startDownload")).leaf =
        true
end

function status()
    local e = {}
    e.status = tonumber(luci.sys.exec("/etc/beamInDocker/getContainerState.sh"))
    luci.http.prepare_content("application/json")
    luci.http.write_json(e)
end

function downloadStatus()
	local d = {}
	d.status = tonumber(luci.sys.exec("/etc/beamInDocker/getDownloadState.sh"))
	d.imageState = tonumber(luci.sys.exec("/etc/beamInDocker/getContainerState.sh"))
	d.downloadMsg = luci.sys.exec("/etc/beamInDocker/getDownloadMsg.sh")
	luci.http.prepare_content("application/json")
    luci.http.write_json(d)
end

function startDownload()
	local e = {}
    e.status = tonumber(luci.sys.exec("/etc/beamInDocker/download.sh"))
    luci.http.prepare_content("application/json")
    luci.http.write_json(e)
end

function show_menu()
    luci.sys.call("touch /etc/config/beamInDocker_show")
    luci.http.redirect(luci.dispatcher.build_url("admin", "vpn", "beamInDocker"))
end

function hide_menu()
    luci.sys.call("rm -rf /etc/config/beamInDocker_show")
    luci.http.redirect(luci.dispatcher.build_url("admin", "status", "overview"))
end