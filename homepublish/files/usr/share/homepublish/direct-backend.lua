-- SPDX-License-Identifier: Apache-2.0
-- Internal-only provider contract; not callable through product wire/CLI.
local A=require('direct-address');local M={}
local function int(x,lo,hi) assert(type(x)=='number' and x%1==0 and x>=lo and x<=hi,'integer');return x end
function M.hostname(s)
 assert(type(s)=='string' and #s>0 and #s<=253 and not s:find('[^a-z0-9.%-]') and not s:find('..',1,true) and s:sub(1,1)~='.' and s:sub(-1)~='.','hostname')
 for l in s:gmatch('[^.]+') do assert(#l<=63 and l:match('^[a-z0-9]') and l:match('[a-z0-9]$'),'hostname label') end
end
local function select(b,p)
 assert(type(b)=='table' and type(p)=='table','typed backend/providers');local port=int(b.port,1,65535);local r
 if b.addressFamily=='hostname' then
  M.hostname(b.host);assert(type(p.resolve)=='function','trusted resolver required');r=p.resolve(b.host)
  assert(type(r)=='table','resolver result');int(r.ttl,1,86400);int(r.observed_at,0,9007199254740990);assert(type(r.resolver)=='string' and #r.resolver>0 and #r.resolver<=128,'resolver identity')
 else assert(b.addressFamily=='ipv4' or b.addressFamily=='ipv6','backend family');r={addresses={b.host}} end
 assert(type(r.addresses)=='table','addresses');local n=0;for k in pairs(r.addresses) do assert(type(k)=='number' and k%1==0 and k>=1,'address key');n=n+1 end;assert(n>0 and n<=64,'answer count')
 local candidates={}
 for i=1,n do
  local s=rawget(r.addresses,i);local w,f=A.parse(s);assert(b.addressFamily=='hostname' or f==b.addressFamily,'literal family')
  assert(A.household(s) and A.in_ranges(s,b.allowed_ranges),'backend outside scope')
  assert(type(p.authorize_backend)=='function' and p.authorize_backend(s,port,f)==true,'backend ownership/management denied')
  local key={};for _,v in ipairs(w) do key[#key+1]=string.format('%04x',v) end
  candidates[#candidates+1]={address=s,family=f,key=table.concat(key)}
 end
 table.sort(candidates,function(a,c) if a.family~=c.family then return a.family=='ipv4' end;if a.key==c.key then return a.address<c.address end;return a.key<c.key end)
 assert(type(p.healthy)=='function','health provider required')
 for _,c in ipairs(candidates) do if p.healthy(c.address,port,c.family)==true then return {address=c.address,family=c.family,port=port,ttl=r.ttl,observed_at=r.observed_at,resolver=r.resolver} end end
 error('no healthy approved backend')
end
function M.select(b,p) local ok,r=pcall(select,b,p);if ok then return r end;return nil,tostring(r) end
return M
