-- SPDX-License-Identifier: Apache-2.0
local M={}
local function need(ok,msg) assert(ok,msg) end
function M.parse(s)
 need(type(s)=='string' and #s<=39,'literal required')
 if not s:find(':',1,true) then
  local a,b,c,d=s:match('^(%d+)%.(%d+)%.(%d+)%.(%d+)$');need(a,'IPv4 literal')
  local w={a,b,c,d};for i,v in ipairs(w) do need(#v<=3 and (v=='0' or v:sub(1,1)~='0') and tonumber(v)<=255,'IPv4 octet');w[i]=tonumber(v) end
  need(w[1]>0 and w[1]<224 and not(w[1]==169 and w[2]==254),'unsafe IPv4')
  return {w[1]*256+w[2],w[3]*256+w[4]},'ipv4'
 end
 need(not s:find('[^0-9a-f:]'),'IPv6 syntax')
 local function split(v)
  local r={};if v=='' then return r end
  need(v:sub(1,1)~=':' and v:sub(-1)~=':' and not v:find('::',1,true),'IPv6 group')
  for x in v:gmatch('[^:]+') do need(#x<=4,'IPv6 width');r[#r+1]=tonumber(x,16) end;return r
 end
 local at=s:find('::',1,true);local w={}
 if at then
  need(not s:find('::',at+2,true),'IPv6 compression')
  local l,r=split(s:sub(1,at-1)),split(s:sub(at+2));need(#l+#r<8,'IPv6 size')
  for _,v in ipairs(l) do w[#w+1]=v end;for _=1,8-#l-#r do w[#w+1]=0 end;for _,v in ipairs(r) do w[#w+1]=v end
 else w=split(s);need(#w==8,'IPv6 size') end
 local loop=true;for i=1,7 do if w[i]~=0 then loop=false end end;loop=loop and w[8]==1
 need(loop or (w[1]>=0x2000 and w[1]<=0x3fff) or (w[1]>=0xfc00 and w[1]<=0xfdff),'unsafe IPv6')
 return w,'ipv6'
end
-- Wildcards belong only to explicitly automatic listeners, never backends/CIDRs.
-- Keep M.parse strict; callers must still authorize ownership and scope.
function M.parse_listener(l)
 need(type(l)=='table','listener required')
 if l.bind_mode=='auto' then
  if l.family=='ipv4' and l.address=='0.0.0.0' then return {0,0},'ipv4' end
  if l.family=='ipv6' and l.address=='::' then return {0,0,0,0,0,0,0,0},'ipv6' end
  error('automatic listener requires exact family wildcard')
 end
 local w,f=M.parse(l.address);need(f==l.family,'listener family');return w,f
end
function M.in_ranges(s,ranges)
 local w,f=M.parse(s);need(type(ranges)=='table','ranges required')
 local found=false;local n=0
 for k in pairs(ranges) do need(type(k)=='number' and k%1==0 and k>=1,'range key');n=n+1 end
 need(n>=1 and n<=32,'range count')
 for i=1,n do
  local v=rawget(ranges,i);need(type(v)=='string','range entry');local base,bits=v:match('^([^/]+)/(%d+)$');need(base,'CIDR')
  local bw,bf=M.parse(base);bits=tonumber(bits);need(bits>=(bf=='ipv4' and 8 or 16) and bits<=(bf=='ipv4' and 32 or 128),'CIDR bits')
  local match=bf==f
  for j=1,#bw do local b=math.max(0,math.min(16,bits));local div=2^(16-b);if math.floor((w[j] or -1)/div)~=math.floor(bw[j]/div) then match=false end;bits=bits-b end
  if match then found=true end
 end
 return found
end
function M.household(s)
 local w,f=M.parse(s);if f=='ipv6' then return true end
 local a,b=math.floor(w[1]/256),w[1]%256
 return a==10 or a==127 or (a==172 and b>=16 and b<=31) or (a==192 and b==168)
end
-- Omitted per-rule CIDRs use fixed LAN safety, never unrestricted Internet.
-- Explicit legacy ranges retain their original (possibly narrower) semantics.
function M.backend_allowed(s,ranges)
 local w,f=M.parse(s)
 if ranges~=nil then return M.household(s) and M.in_ranges(s,ranges) end
 if f=='ipv6' then return w[1]>=0xfc00 and w[1]<=0xfdff end
 return M.household(s)
end
return M
