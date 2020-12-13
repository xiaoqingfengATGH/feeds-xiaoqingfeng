local s = require "luci.sys"
local net = require"luci.model.network".init()
local ifaces = s.net:devices()
local m, s, o
mp = Map("beamInDocker", translate("Beam(Docker)"))
mp.description = translate("An internet access accelerator utility")
mp:section(SimpleSection).template = "beamInDocker/index"

s = mp:section(TypedSection, "service")
s.anonymous = true

enabled = s:option(Flag, "enabled", translate("Enabled"))
enabled.default = 0
enabled.rmempty = false

o = s:option(DummyValue, "beamInDocker_status", translate("Current Condition"))
o.default = translate("Detecting...")
o.template = "beamInDocker/status"

version = s:option(DummyValue, "version", translate("Version"))
version.rmempty = false
--[[
o = s:option(Button, "clear_ipset", translate("Check updates"), translate("Check for new beam docker image version."))
o.inputstyle = "remove"
function o.write(a, b)
    luci.sys.call("/etc/init.d/" .. appname .. " stop && /usr/share/" .. appname .. "/iptables.sh flush_ipset && /etc/init.d/" .. appname .. " restart")
end
]]
--[[
guiport = s:option(Value, "guiport", translate("GUI Port"))
guiport.datatype = "port"
guiport.optional = false
guiport.rmempty = false
]]
o = s:option(Button, "psw_plugin", translate("Work with PSW"), translate("Add beam to PSW node list and set it to default tcp proxy. Please confirm beam is running before operation. After the operation is completed, your browser will jump to the home page of PSW."))
o.inputstyle = "apply"
function o.write(a, b)
    luci.sys.call("/etc/beamInDocker/pswPlugin.sh")
	local pswurl = luci.dispatcher.build_url("admin/vpn/passwall")
	luci.http.write("<script>location.href='"..pswurl.."';</script>")
end

mp:append(Template("beamInDocker/download"))

local apply=luci.http.formvalue("cbi.apply")
if apply then
    io.popen("/etc/init.d/beamInDocker restart")
end
return mp
