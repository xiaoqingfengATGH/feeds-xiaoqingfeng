-- SPDX-License-Identifier: Apache-2.0
local M = {}
local function port(n)
 return type(n)=='number' and n==math.floor(n) and n>=1024 and n<=65535
end
local function ipv4(s)
 if type(s)~='string' then return false end
 local a,b,c,d=s:match('^(%d+)%.(%d+)%.(%d+)%.(%d+)$')
 if not a then return false end
 for _,v in ipairs({a,b,c,d}) do if tonumber(v)>255 or tostring(tonumber(v))~=v then return false end end
 return true
end
local function localip(s)
 return ipv4(s) and (s:match('^127%.') or s:match('^10%.') or s:match('^192%.168%.') or (tonumber(s:match('^172%.(%d+)%.') or 0)>=16 and tonumber(s:match('^172%.(%d+)%.') or 0)<=31))
end
local function hostname(s)
 if type(s)~='string' or #s>253 or not s:find('%.') or s:find('[^a-z0-9.%-]') or s:find('%.%.') or s:sub(1,1)=='.' or s:sub(-1)=='.' then return false end
 for label in s:gmatch('[^.]+') do
  if #label>63 or not label:match('^[a-z0-9]') or not label:match('[a-z0-9]$') then return false end
 end
 return true
end
local function path(s)
 return type(s)=='string' and s:match('^/[A-Za-z0-9_./%-]+$') and not s:find('..',1,true) and not s:find('//',1,true)
end
function M.validate(c)
 if type(c)~='table' then return nil,'configuration required' end
 local allowed={listen=true,port=true,cert=true,key=true,runtime=true,hosts=true}
 for k in pairs(c) do if not allowed[k] then return nil,'unknown option' end end
 if not localip(c.listen) or not port(c.port) then return nil,'isolated listener required' end
 if not path(c.runtime) or not (c.runtime:match('^/tmp/homedirect[%w_%-]*$') or c.runtime=='/var/run/homedirect') then return nil,'isolated runtime required' end
 if not path(c.cert) or not path(c.key) then return nil,'unsafe TLS path' end
 if type(c.hosts)~='table' or #c.hosts<1 or #c.hosts>16 then return nil,'1..16 hosts required' end
 local seen={}
 for i,h in pairs(c.hosts) do
  if type(i)~='number' or i<1 or i>#c.hosts or type(h)~='table' then return nil,'invalid host list' end
  for k in pairs(h) do if k~='name' and k~='upstream' then return nil,'unknown host option' end end
  if not hostname(h.name) or seen[h.name] then return nil,'invalid/duplicate hostname' end
  seen[h.name]=true
  if type(h.upstream)~='string' then return nil,'upstream required' end
  local ip,p=h.upstream:match('^http://([%d.]+):(%d+)$')
  if not localip(ip) or not port(tonumber(p)) then return nil,'explicit private HTTP upstream on non-management port required' end
 end
 return true
end
function M.render(c)
 local ok,err=M.validate(c); if not ok then return nil,err end
 local r=c.runtime
 local out={ 'worker_processes 1;', 'pid '..r..'/nginx.pid;', 'error_log '..r..'/error.log;', 'events { worker_connections 64; }', 'http {', 'access_log off;', 'client_body_temp_path '..r..'/body;', 'proxy_temp_path '..r..'/proxy;', 'ssl_certificate '..c.cert..';', 'ssl_certificate_key '..c.key..';', 'ssl_protocols TLSv1.2 TLSv1.3;', 'server { listen '..c.listen..':'..c.port..' ssl default_server; server_name _; return 444; }' }
 for _,h in ipairs(c.hosts) do
  out[#out+1]='server { listen '..c.listen..':'..c.port..' ssl; server_name '..h.name..'; location / { proxy_pass '..h.upstream..'; proxy_set_header Host $host; proxy_set_header X-Forwarded-For $remote_addr; proxy_set_header X-Forwarded-Proto https; proxy_connect_timeout 5s; proxy_read_timeout 30s; } }'
 end
 out[#out+1]='}'
 return table.concat(out,'\n')..'\n'
end
return M
