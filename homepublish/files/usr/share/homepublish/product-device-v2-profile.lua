-- SPDX-License-Identifier: Apache-2.0
-- Installed root-only capability profile. NOT production dependency selection.
-- Private binaries remain fixtures; no RPC-configurable paths or callbacks.
local root='/tmp/homepublish-tcp-p3'
local function backend(a,p)return a=='127.0.0.1' and (p==49545 or p==49546 or p==49547 or p==49548 or p==49556) end
local function listener(l)return l.address=='fd89:878e:a47f:0:0:0:0:1' and (l.internal_port==49543 or l.internal_port==49550) end
return require('product-v2-runtime').new({
 name='homepublish-p3-controller',root=root..'/controller-runtime',nginx=root..'/nginx-private',sslh=root..'/sslh-select.private',mixed_ports={https=49544,reject=49549},
 available=function()return os.execute('test -f '..root..'/controller-fixture/authorized && test -x '..root..'/nginx-private && test -x '..root..'/sslh-select.private')==0 end,
 authorize=function(c)
  if #c.access_profile.listeners~=1 then return false end
  local l=c.access_profile.listeners[1];if l.address~='fd89:878e:a47f:0:0:0:0:1' or l.port~=49543 or l.network~='lan' then return false end
  for _,s in ipairs(c.services) do
   if s.backend.addressFamily~='ipv4' or not backend(s.backend.host,s.backend.port) or s.backend.backup then return false end
   if s.type=='https_proxy' then
    local ref=s.certificate_mode=='inherit' and c.default_certificate_ref or s.certificate_ref
    if s.hostname~='home.iwonderful.top' or ref~='acme:home_rsa' or (s.backend.port~=49545 and s.backend.port~=49556) then return false end
   elseif s.type=='tls_passthrough' then if s.hostname~='tls.fixture.home' or s.backend.port~=49546 then return false end
   elseif s.type=='ssh' then if s.backend.port~=49547 then return false end
   elseif s.type=='tcp_forward' then if s.listen_port~=49550 or (s.backend.port~=49546 and s.backend.port~=49548) then return false end
   else return false end
  end;return true
 end,
 authorize_listener=listener,authorize_backend=backend,
 narrow=function(s)return (s:gsub('fd89:878e:a47f:0:0:0:0:1','::1')) end,
 probe_address=function()return '::1' end,
 passthrough_trust=root..'/controller-fixture/tls.pem'
})
