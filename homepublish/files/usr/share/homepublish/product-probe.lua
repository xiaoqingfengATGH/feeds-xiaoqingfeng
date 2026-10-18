-- SPDX-License-Identifier: Apache-2.0
-- Optional router-origin TCP diagnostic. Never calls the controller or writes state.
local source=debug.getinfo(1,'S').source:sub(2):match('^(.*)/')
local A=dofile(source..'/direct-address.lua')
local M={}
function M.probe(request,d)
 local out={ok=false,summary='Probe request rejected',phase='request',reason='INVALID_REQUEST',origin='router',config_source='saved',public_reachability='unverified',application_health='unverified',timeout_ms=5000}
 local function result(phase,reason,summary)out.phase=phase;out.reason=reason;out.summary=summary;return out end
 if type(request)~='table' then return out end
 for k in pairs(request) do if k~='service_id' then return out end end
 local id=request.service_id
 if type(id)~='string' or #id<1 or #id>64 or not id:match('^[a-zA-Z0-9_-]+$') then return out end
 out.service_id=id
 local ok,state=pcall(d.snapshot)
 if not ok or type(state)~='table' then return result('configuration','STATE_UNAVAILABLE','Saved configuration unavailable') end
 out.saved_revision=state.saved_revision;out.active_revision=state.active_revision
 if not state.saved_config then return result('configuration','NO_SAVED_CONFIG','No saved configuration') end
 local service
 for _,s in ipairs(state.saved_config.services or {}) do if s.service_id==id then service=s;break end end
 if not service then return result('configuration','SERVICE_NOT_FOUND','Service not present in the saved revision') end
 if service.enabled==false then return result('configuration','SERVICE_DISABLED','Saved service is disabled; no traffic sent') end
 local b=service.backend
 if type(b)~='table' then return result('configuration','INVALID_BACKEND','Saved backend unavailable') end
 out.backend={host=b.host,port=b.port};out.transport='tcp';out.backup_tested=false
 local addresses={b.host}
 if b.addressFamily=='hostname' then
  local r=d.bounded('resolve',2000,function()return d.resolve(b.host) end)
  if not r or not r.ok then return result('resolve',r and r.reason or 'RESOLVE_FAILED','Backend DNS resolution failed or timed out') end
  addresses=r.addresses
 end
 if type(addresses)~='table' or #addresses<1 or #addresses>64 then return result('resolve','RESOLVE_FAILED','No usable backend DNS answers') end
 -- Validate every answer before any connection, matching fail-closed runtime scope.
 local candidates={}
 for _,address in ipairs(addresses) do
  local valid,_,family=pcall(A.parse,address)
  if not valid or not A.backend_allowed(address,b.allowed_ranges) then return result('scope','BACKEND_OUTSIDE_SCOPE','Backend address is outside permitted household addresses; no connection attempted') end
  candidates[#candidates+1]={address=address,family=family}
 end
 table.sort(candidates,function(a,b)return a.family==b.family and a.address<b.address or a.family~=b.family and a.family=='ipv4' end)
 local selected=candidates[1];out.backend.address=selected.address;out.backend.family=selected.family;out.addresses_considered=#candidates;out.addresses_tested=1
 local r=d.bounded('connect',3000,function()return d.connect(selected.address,b.port,selected.family) end)
 if not r or not r.ok then
  local reason=r and r.reason or 'CONNECT_FAILED'
  local details={CONNECTION_REFUSED='Connection refused',TIMEOUT='Connection timed out',NETWORK_UNREACHABLE='Network unreachable',HOST_UNREACHABLE='Host unreachable',PERMISSION_DENIED='Connection denied by router policy',SOCKET_UNAVAILABLE='Router socket unavailable',PROBE_UNAVAILABLE='Probe worker unavailable',PROBE_FAILED='Probe worker failed'}
  return result('connect',reason,(details[reason] or 'TCP connection failed')..' from router to the selected saved backend address')
 end
 out.ok=true
 return result('complete','TCP_CONNECTED','Router TCP connection to the selected saved backend succeeded; application/TLS and public access are unverified')
end
return M
