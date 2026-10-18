-- SPDX-License-Identifier: Apache-2.0
-- Bounded non-executable wire format, shared by disk and the fixed CLI.
-- s<byte-count>:bytes, i<integer>;, b0/b1, t<pair-count>:key/value pairs.
local M={}; local MAX=262144
function M.encode(value)
 local nodes,seen=0,{}
 local function enc(v,depth)
  nodes=nodes+1; assert(depth<=24 and nodes<=8192,'wire limit')
  if type(v)=='string' then assert(#v<=MAX,'wire limit'); return 's'..#v..':'..v end
  if type(v)=='boolean' then return v and 'b1' or 'b0' end
  if type(v)=='number' then assert(v%1==0 and math.abs(v)<=9007199254740991,'wire integer'); return 'i'..string.format('%.0f',v)..';' end
  assert(type(v)=='table' and getmetatable(v)==nil and not seen[v],'wire type or cycle'); seen[v]=true
  local keys={}; for k in pairs(v) do assert(type(k)=='string' or (type(k)=='number' and k%1==0 and k>=1),'wire key'); keys[#keys+1]=k end
  table.sort(keys,function(a,b) if type(a)~=type(b) then return type(a)<type(b) end return a<b end)
  local r={'t'..#keys..':'};for _,k in ipairs(keys) do r[#r+1]=enc(k,depth+1);r[#r+1]=enc(v[k],depth+1) end
  seen[v]=nil; return table.concat(r)
 end
 local out='HP1'..enc(value,0); assert(#out<=MAX,'wire limit'); return out
end
function M.decode(s)
 assert(type(s)=='string' and #s<=MAX and s:sub(1,3)=='HP1','wire header/limit')
 local pos,nodes=4,0
 local function number_until(ending)
  local stop=s:find(ending,pos,true);assert(stop and stop-pos<=17,'wire number')
  local text=s:sub(pos,stop-1); assert(text:match('^%-?%d+$'),'wire integer')
  local n=tonumber(text);assert(n and math.abs(n)<=9007199254740991 and n%1==0,'wire integer');pos=stop+1;return n
 end
 local function dec(depth)
  nodes=nodes+1; assert(depth<=24 and nodes<=8192,'wire limit')
  local tag=s:sub(pos,pos);pos=pos+1
  if tag=='s' then local n=number_until(':');assert(n>=0 and pos+n-1<=#s,'wire string');local v=s:sub(pos,pos+n-1);pos=pos+n;return v end
  if tag=='i' then return number_until(';') end
  if tag=='b' then local v=s:sub(pos,pos);assert(v=='0' or v=='1','wire boolean');pos=pos+1;return v=='1' end
  assert(tag=='t','wire tag');local n=number_until(':');assert(n>=0 and n<=4096,'wire table');local r={}
  for _=1,n do local k=dec(depth+1);assert(type(k)=='string' or (type(k)=='number' and k%1==0 and k>=1),'wire key');assert(r[k]==nil,'wire duplicate key');r[k]=dec(depth+1) end
  return r
 end
 local value=dec(0); assert(pos==#s+1,'wire trailing data');return value
end
return M
