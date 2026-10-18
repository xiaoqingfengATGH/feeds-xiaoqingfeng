-- SPDX-License-Identifier: Apache-2.0
local source=debug.getinfo(1,'S').source:sub(2):match('^(.*)/')
local core=dofile(source..'/core.lua')
local M={}
local function integer(s,lo,hi)
 if type(s)~='string' or not s:match('^%d+$') then return nil end
 local n=tonumber(s); if n<lo or n>hi then return nil end; return n
end
local function server(s)
 if type(s)~='string' or #s>253 or s:find('[^a-z0-9.%-:]') then return false end
 local host,p=s:match('^([^:]+):(%d+)$');host=host or s
 if s:find(':') and not p then return false end
 if p and not integer(p,1,65535) then return false end
 if host:sub(1,1)=='.' or host:sub(-1)=='.' or host:find('..',1,true) then return false end
 for label in host:gmatch('[^.]+') do
  if #label>63 or not label:match('^[a-z0-9]') or not label:match('[a-z0-9]$') then return false end
 end
 return true
end
function M.validate(c,hosts)
 if type(c)~='table' then return nil,'service section required' end
 local allowed={publication_enabled=true,router_token_file=true,enabled=true,exposure_approved=true,listen=true,port=true,bind_port=true,ttl=true,stun_server=true,http_server=true,cert=true,key=true}
 for k in pairs(c) do if k:sub(1,1)~='.' and not allowed[k] then return nil,'unknown service option' end end
 if c.enabled~='0' and c.enabled~='1' then return nil,'enabled must be 0 or 1' end
 if c.exposure_approved~='0' and c.exposure_approved~='1' then return nil,'approval must be 0 or 1' end
 local publish=c.publication_enabled or '0'
 if publish~='0' and publish~='1' then return nil,'publication_enabled must be 0 or 1' end
 if c.router_token_file~=nil and c.router_token_file~='/etc/homepublish/router.token' then return nil,'dedicated private token path required' end
 if publish=='1' and c.router_token_file~='/etc/homepublish/router.token' then return nil,'publication token reference required' end
 if c.enabled=='0' then return {state='disabled',publication='disabled'} end
 if c.exposure_approved~='1' then return nil,'explicit exposure approval required' end
 local ttl=integer(c.ttl,1,120)
 local bind=integer(c.bind_port,1024,65535)
 local port=integer(c.port,1024,65535)
 if not ttl or not bind or not port or bind==port then return nil,'invalid TTL or isolated ports' end
 if c.listen~='127.0.0.1' then return nil,'forward target must be loopback' end
 if not server(c.stun_server) or not server(c.http_server) then return nil,'invalid discovery server' end
 if c.cert~='/etc/homepublish/cert.pem' or c.key~='/etc/homepublish/key.pem' then return nil,'dedicated TLS paths required' end
 local cfg={listen=c.listen,port=port,cert='/tmp/homepublish-service/cert.pem',key='/tmp/homepublish-service/key.pem',runtime='/tmp/homepublish-service',hosts=hosts}
 local ok,err=core.validate(cfg);if not ok then return nil,err end
 return {state='configured',publication=publish=='1' and 'configured' or 'disabled',router_token_file=c.router_token_file,ttl=ttl,bind_port=bind,stun=c.stun_server,http=c.http_server,nginx=cfg}
end
function M.load(cursor)
 local c=cursor:get_all('homepublish','main')
 local hosts={}
 local invalid=false
 cursor:foreach('homepublish','host',function(s)
  for k in pairs(s) do if k:sub(1,1)~='.' and k~='name' and k~='upstream' then invalid=true end end
  hosts[#hosts+1]={name=s.name,upstream=s.upstream}
 end)
 if invalid then return nil,'unknown host option' end
 return M.validate(c,hosts)
end
return M
