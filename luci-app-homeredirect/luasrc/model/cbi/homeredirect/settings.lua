local m, s, o
local sys = require "luci.sys"

mp = Map("homeredirect", translate("Home Redirect - Port forwarding utility"))
mp.description = translate("HomeRedirect is a customized port forwarding utility for HomeLede. It supports TCP / UDP protocol, IPv4 and IPv6, cross-family v6-to-v4 forwarding, dynamic domain destinations and optional TLS listeners.")
mp:section(SimpleSection).template  = "homeredirect/index"

s = mp:section(TypedSection, "global")
s.anonymous = true

enabled = s:option(Flag, "enabled", translate("Master switch"))
enabled.default = 0
enabled.rmempty = false

cert = s:option(Value, "cert", translate("TLS certificate"),
	translate("PEM certificate for TLS listeners (e.g. /etc/acme/your.domain/fullchain.cer). Leave empty when no TLS rule is used."))
cert.optional = true
cert.rmempty = true

key = s:option(Value, "key", translate("TLS private key"),
	translate("PEM private key matching the certificate above."))
key.optional = true
key.rmempty = true

s = mp:section(TypedSection, "redirect", translate("Redirect Configuration"))
s.addremove = true
s.anonymous = true
s.template = "cbi/tblsection"
s.sortable = true

enabled = s:option(Flag, "enabled", translate("Enabled"))
enabled.rmempty = false

name = s:option(Value, "name", translate("Name"))
name.optional = false
name.rmempty = false

proto = s:option(ListValue, "proto", translate("Transport Protocol"),
	translate("Cross-family modes (TCP/IPv6 to IPv4) work under CGNAT where the router only has a public IPv6 address. The destination side always accepts IPv4, IPv6 and domain names."))
proto.default = "tcp6"
proto:value("tcp4", "TCP/IPv4")
proto:value("udp4", "UDP/IPv4")
proto:value("tcp6", "TCP/IPv6")
proto:value("udp6", "UDP/IPv6")
proto:value("tls4", "TLS/IPv4")
proto:value("tls6", "TLS/IPv6")

src_dport = s:option(Value, "src_dport", translate("Source Port"))
src_dport.datatype = "port"
src_dport.optional = false
src_dport.rmempty = false

dest_ip = s:option(Value, "dest_ip", translate("Destination Address"),
	translate("IPv4 / IPv6 address or domain name. Domain names are re-resolved on every connection, so a changing target address keeps working."))
dest_ip.optional = false
dest_ip.rmempty = false

dest_port = s:option(Value, "dest_port", translate("Destination Port"))
dest_port.datatype = "port"
dest_port.optional = false
dest_port.rmempty = false

ipv6only = s:option(Flag, "ipv6only", translate("IPv6 only"),
	translate("Refuse IPv4-mapped connections on IPv6 listeners (default on). Turn off to accept both families on one socket."))
ipv6only.default = ipv6only.enabled
ipv6only.rmempty = false

o = s:option(DummyValue, "rs", translate("Status"))
o.default = "…"

return mp
