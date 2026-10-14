-- SPDX-License-Identifier: Apache-2.0
-- Fixed transport adapter: JSON request -> CLI wire -> JSON response.
local source=debug.getinfo(1,'S').source:sub(2):match('^(.*)/')
local json=dofile(source..'/product-json.lua')
local wire=dofile(source..'/product-wire.lua')
local function run()
 local bytes=io.stdin:read(262145) or ''
 if arg[1]=='response' and #arg==1 then
  local ok,result=pcall(wire.decode,bytes:gsub('\n$',''))
  io.write(json.encode(ok and result or {error='Request rejected or state unavailable'}),'\n');return
 end
 assert(#arg==1 and ({certificates=true,status=true,validate=true,save=true,stop=true,start=true,apply=true})[arg[1]],'unsupported method')
 local r=json.decode(bytes);assert(type(r)=='table','request object')
 -- uhttpd injects transport session metadata after its ACL check. Never send it to the controller.
 if r.ubus_rpc_session~=nil then
  assert(type(r.ubus_rpc_session)=='string' and #r.ubus_rpc_session==32 and r.ubus_rpc_session:match('^[0-9a-f]+$'),'invalid session metadata')
  r.ubus_rpc_session=nil
 end
 local fields=arg[1]=='save' and {expected_revision=true,config=true} or arg[1]=='validate' and {config=true} or (arg[1]=='start' or arg[1]=='apply') and {revision=true,approved=true} or {}
 for k in pairs(r) do assert(fields[k],'unknown request field') end
 r.action=arg[1];io.write(wire.encode(r))
end
if not pcall(run) then os.exit(1) end
