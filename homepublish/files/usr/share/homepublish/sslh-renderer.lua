-- SPDX-License-Identifier: Apache-2.0
-- Pure mixed HTTPS/exact-SNI compiler; fixed runtime ports are trusted provider
-- input, never canonical/client configuration. No launch or activation authority.
local A=require('direct-address');local B=require('direct-backend');local M={}
local function render(plan,p)
 local ports=assert(p.mixed_ports,'owned internal endpoints required')
 local required=#plan.services>0 and {'https','reject'} or {'reject'}
 local has_http=plan.http_services and #plan.http_services>0
 if has_http then required[#required+1]='http' end
 local seen={};for _,k in ipairs(required) do local v=ports[k];assert(type(v)=='number' and v%1==0 and v>=1024 and v<=65535 and not seen[v],'internal port');seen[v]=true end
 local listen={};local public
 for _,l in ipairs(plan.access_profile.listeners) do
  local _,f=A.parse_listener(l);assert(f==l.family and l.protocol=='tcp','listener');assert(p.authorize_listener(l)==true,'external listener denied')
  assert(not seen[l.internal_port],'internal/external collision');public=public or l.internal_port;assert(public==l.internal_port,'shared port')
  listen[#listen+1]='{ host: "'..l.address..'"; port: "'..l.internal_port..'"; }'
 end
 local protocols={};local hosts={}
 local function route(host,address,port,proxy)
  B.hostname(host);assert(not hosts[host],'duplicate SNI');hosts[host]=true
  protocols[#protocols+1]='{ name: "tls"; host: "'..address..'"; port: "'..port..'"; sni_hostnames: [ "'..host..'" ];'..(proxy and ' proxyprotocol: 1;' or '')..' }'
 end
 for _,s in ipairs(plan.services) do route(s.hostname,'127.0.0.1',ports.https,true) end
 if has_http then protocols[#protocols+1]='{ name: "http"; host: "127.0.0.1"; port: "'..ports.http..'"; proxyprotocol: 1; }' end
 local backends={}
 for _,s in ipairs(plan.passthrough or {}) do local b,e=B.select(s.backend,p);assert(b,e);route(s.hostname,b.address,b.port,false);backends[#backends+1]=b end
 if plan.ssh then
  local b,e=B.select(plan.ssh.backend,p);assert(b,e)
  protocols[#protocols+1]='{ name: "ssh"; host: "'..b.address..'"; port: "'..b.port..'"; }'
  backends[#backends+1]=b
 end
 protocols[#protocols+1]='{ name: "anyprot"; host: "127.0.0.1"; port: "'..ports.reject..'"; }'
 local r
 if #plan.services>0 then
 local internal={services=plan.services,access_profile={listeners={{family='ipv4',address='127.0.0.1',protocol='tcp',interface='lo',zone='loopback',internal_port=ports.https,public_port=public}}}}
 local ip={};for k,v in pairs(p) do ip[k]=v end
 ip.authorize_listener=function(l)return l.address=='127.0.0.1' and l.internal_port==ports.https end
 local e;r,e=require('direct-renderer').render(internal,ip);assert(r,e)
 -- Only the exact loopback sslh peer supplies PROXY to terminated HTTPS.
 r.configuration=r.configuration:gsub('listen 127%.0%.0%.1:'..ports.https..' ssl','listen 127.0.0.1:'..ports.https..' ssl proxy_protocol')
 r.configuration=r.configuration:gsub('http {','http {\nset_real_ip_from 127.0.0.1;\nreal_ip_header proxy_protocol;',1)
 else
 r={configuration='worker_processes 1;\ndaemon off;\npid nginx.pid;\nerror_log stderr error;\nevents { worker_connections 64; }\n',backends={},activation_ready=false,blocker='fixed runtime provider and authoritative DNS/ownership readiness required'}
 end
 if has_http then
  local internal={services=plan.http_services,access_profile={listeners={{family='ipv4',address='127.0.0.1',protocol='tcp',interface='lo',zone='loopback',internal_port=ports.http,public_port=public}}}}
  local ip={};for k,v in pairs(p) do ip[k]=v end
  ip.authorize_listener=function(l)return l.address=='127.0.0.1' and l.internal_port==ports.http end
  local http,e=require('direct-renderer').render_http(internal,ip);assert(http,e)
  if #plan.services>0 then
   r.configuration=r.configuration:gsub('}\n$',function()return http.http_servers..'}\n' end,1)
  else
   r.configuration=http.configuration:gsub('http {','http {\nset_real_ip_from 127.0.0.1;\nreal_ip_header proxy_protocol;',1)
  end
  for _,b in ipairs(http.backends) do r.backends[#r.backends+1]=b end
 end
 r.configuration=r.configuration..'stream { server { listen 127.0.0.1:'..ports.reject..'; return ""; } }\n'
 r.sslh_configuration='foreground: true; numeric: true; transparent: false; timeout: 1;\nlisten: ( '..table.concat(listen,', ')..' );\nprotocols: ( '..table.concat(protocols,',\n')..' );\non-timeout: "anyprot";\n'
 for _,b in ipairs(backends) do r.backends[#r.backends+1]=b end
 return r
end
function M.render(plan,p)local ok,r=pcall(render,plan,p);if ok then return r end;return nil,tostring(r) end
return M
