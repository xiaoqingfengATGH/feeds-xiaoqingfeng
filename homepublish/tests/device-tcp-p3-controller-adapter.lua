-- Fixed non-installed adapter. No client-selected ports, paths or binaries.
local M={};local root='/tmp/homepublish-tcp-p3';local run=root..'/controller-runtime'
function M.runtime_plan(c)
 local p,e=require('canonical-v2').validate(c);if not p then return nil,e end
 local enabled={};for _,s in ipairs(p.services) do if s.enabled then enabled[#enabled+1]=s end end;p.services=enabled
 return p
end
function M.plan(c)
 local p={mixed_ports={reject=49549},authorize_listener=function(l)return l.address=='fd89:878e:a47f:0:0:0:0:1' and (l.internal_port==49543 or l.internal_port==49550) end,authorize_backend=function(a,port)return a=='127.0.0.1' and (port==49546 or port==49548) end,healthy=function()return true end,certificate_snapshot=function()error('no certificate in this fixed scope')end}
 if #c.services~=2 or c.services[1].service_id~='tls' or c.services[1].type~='tls_passthrough' or c.services[1].hostname~='tls.fixture.home' or c.services[2].service_id~='raw' or c.services[2].type~='tcp_forward' then return nil,'fixed controller scope denied' end
 local r,e=require('direct-renderer').render(c,p);if not r then return nil,e end
 r.configuration=r.configuration:gsub('fd89:878e:a47f:0:0:0:0:1','::1');r.sslh_configuration=r.sslh_configuration:gsub('fd89:878e:a47f:0:0:0:0:1','::1')
 r.services=c.services;return r
end
local function group()return require('product-procd-group').new({name='homepublish-p3-controller',root=run,nginx=root..'/nginx-private',sslh=root..'/sslh-select.private'})end
function M.start(p,g)return group().start(p,g)end
function M.stop()return group().stop()end
function M.readiness(p)
 local ok=group().healthy();local out={}
 for _,s in ipairs(p.services) do
  local port=s.service_id=='tls' and 49543 or 49550
  local ready=false
  for attempt=1,3 do
   ready=os.execute("curl -q --noproxy '*' --cacert "..root.."/controller-fixture/tls.pem --connect-timeout 1 --max-time 2 --fail --silent --output /dev/null --resolve 'tls.fixture.home:"..port..":[::1]' https://tls.fixture.home:"..port.."/")==0
   if ready then break end;os.execute('sleep 1')
  end
  local marker=io.open(root..'/controller-stale-generation');local generation=p.generation;if marker then marker:close();generation=0 end
  out[s.service_id]={ready=ok and ready,generation=generation}
 end
 for _,v in pairs(out) do if not v.ready then return false,out end end
 return ok,out
end
function M.renew()return group().healthy()end
return M
