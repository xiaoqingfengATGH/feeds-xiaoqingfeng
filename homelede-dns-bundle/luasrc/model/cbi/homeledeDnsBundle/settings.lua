local s = require "luci.sys"
local m, s, o
mp = Map("homeledeDnsBundle", translate("Homelede DNS Control Panel"))
mp.description = translate("Provide centralized control for Homelede diversion resolution DNS solution")
mp:section(SimpleSection).template  = "homeledeDnsBundle/index"

s = mp:section(TypedSection, "global")
s.anonymous = true

enabled = s:option(Flag, "enabled", translate("Master switch"),
    translate("Controls whether the Homelede DNS suite is enabled."))
enabled.default = 0
enabled.rmempty = false

adBlockEnabled = s:option(Flag, "adBlock", translate("AdBlock switch"),
    translate("Control whether the advertising filtering component is enabled."))
adBlockEnabled.default = 1
adBlockEnabled.rmempty = false

shuntResolutionEnabled = s:option(Flag, "shuntResolution", translate("ShuntResolution switch"),
    translate("Control whether to open DNS resolution for domestic and overseas diversion."))
shuntResolutionEnabled.default = 1
shuntResolutionEnabled.rmempty = false

s = mp:section(TypedSection, "adBlock", translate("Ad block configuration"))
s.anonymous = true
---- Port
o = s:option(Value, "webUIPort", translate("UI Port"), 
    translate("AdGuardHome Configuration UI Port."))
o.placeholder = 3000
o.default     = 3000
o.datatype    = "port"
o.rempty      = false

local apply=luci.http.formvalue("cbi.apply")
if apply then
    io.popen("/etc/init.d/HomeledeDnsBundle restart")
end

return mp
