-- SPDX-License-Identifier: Apache-2.0
-- Separate optional RPC path: never queued on the runtime/control channel.
local source=debug.getinfo(1,'S').source:sub(2):match('^(.*)/')
local J=dofile(source..'/product-json.lua')
local P=dofile(source..'/product-probe.lua')
local D=dofile(source..'/product-probe-device.lua')
local function failure(phase,reason,summary)
 return {ok=false,phase=phase,reason=reason,summary=summary,origin='router',config_source='saved',public_reachability='unverified',application_health='unverified'}
end
local function run()
 if #arg~=0 then return failure('request','INVALID_REQUEST','Probe request rejected') end
 local bytes=io.stdin:read(4097) or ''
 if #bytes>4096 then return failure('request','INVALID_REQUEST','Probe request too large') end
 local ok,r=pcall(J.decode,bytes)
 if not ok or type(r)~='table' then return failure('request','INVALID_REQUEST','Probe request rejected') end
 -- rpcd has already checked ACL. Strip only valid transport metadata.
 if r.ubus_rpc_session~=nil then
  if type(r.ubus_rpc_session)~='string' or #r.ubus_rpc_session~=32 or not r.ubus_rpc_session:match('^[0-9a-f]+$') then return failure('request','INVALID_REQUEST','Probe request rejected') end
  r.ubus_rpc_session=nil
 end
 return P.probe(r,D.new())
end
local ok,result=pcall(run)
io.stdout:write(J.encode(ok and result or failure('probe','PROBE_UNAVAILABLE','Optional probe unavailable; normal status and runtime are unaffected')),'\n')
