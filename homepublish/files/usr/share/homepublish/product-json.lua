-- SPDX-License-Identifier: Apache-2.0
-- Bounded JSON transport only. Canonical validation remains authoritative.
local M={}
function M.decode(s)
 assert(type(s)=='string' and #s<=262144,'JSON limit')
 local i,nodes=1,0
 local function ws() local _,e=s:find('^[ \t\r\n]*',i);i=(e or i-1)+1 end
 local value
 local function str()
  assert(s:sub(i,i)=='"','JSON string');i=i+1;local out={}
  while i<=#s do
   local c=s:sub(i,i);i=i+1
   if c=='"' then return table.concat(out) end
   if c=='\\' then
    local e=s:sub(i,i);i=i+1
    local escapes={['"']='"',['\\']='\\',['/']='/',b='\b',f='\f',n='\n',r='\r',t='\t'}
    if e=='u' then
     local h=s:sub(i,i+3);assert(#h==4 and not h:find('[^%x]'),'JSON unicode');i=i+4;local u=tonumber(h,16)
     if u>=0xd800 and u<=0xdbff then
      assert(s:sub(i,i+1)=='\\u','JSON surrogate pair');i=i+2
      local low=s:sub(i,i+3);assert(#low==4 and not low:find('[^%x]'),'JSON unicode');i=i+4
      local l=tonumber(low,16);assert(l>=0xdc00 and l<=0xdfff,'JSON surrogate pair')
      u=0x10000+(u-0xd800)*1024+(l-0xdc00)
     else assert(u<0xdc00 or u>0xdfff,'JSON surrogate pair') end
     c=u<128 and string.char(u) or u<2048 and string.char(192+math.floor(u/64),128+u%64) or u<65536 and string.char(224+math.floor(u/4096),128+math.floor(u/64)%64,128+u%64) or string.char(240+math.floor(u/262144),128+math.floor(u/4096)%64,128+math.floor(u/64)%64,128+u%64)
    else c=assert(escapes[e],'JSON escape') end
   else assert(c:byte()>=32,'JSON control') end
   out[#out+1]=c
  end
  error('JSON unterminated string')
 end
 value=function(depth)
  nodes=nodes+1;assert(depth<=24 and nodes<=8192,'JSON limit');ws();local c=s:sub(i,i)
  if c=='"' then return str() end
  if c=='{' or c=='[' then
   i=i+1;ws();local r={};local close=c=='{' and '}' or ']';if s:sub(i,i)==close then i=i+1;return r end
   while true do
    local k=c=='{' and str() or #r+1
    if c=='{' then ws();assert(s:sub(i,i)==':','JSON colon');i=i+1 end
    assert(r[k]==nil,'JSON duplicate');r[k]=value(depth+1);ws();local t=s:sub(i,i);i=i+1
    if t==close then return r end
    assert(t==',','JSON separator');ws()
   end
  end
  for text,v in pairs({['true']=true,['false']=false}) do if s:sub(i,i+#text-1)==text then i=i+#text;return v end end
  local text=s:match('^%-?%d+',i);assert(text and not text:match('^%-?0%d'),'JSON integer');i=i+#text;local n=tonumber(text);assert(math.abs(n)<=9007199254740991,'JSON integer');return n
 end
 local r=value(0);ws();assert(i==#s+1,'JSON trailing');return r
end
function M.encode(v)
 local function enc(x,field)
  if type(x)=='string' then return '"'..x:gsub('[%z\1-\31\\"]',function(c) return string.format('\\u%04x',c:byte()) end)..'"' end
  if type(x)=='boolean' then return x and 'true' or 'false' end
  if type(x)=='number' then return string.format('%.0f',x) end
  assert(type(x)=='table','JSON type');local out={}
  if #x==0 and (field=='certificates' or field=='sans') then return '[]' end
  if #x>0 then for _,y in ipairs(x) do out[#out+1]=enc(y) end;return '['..table.concat(out,',')..']' end
  for k,y in pairs(x) do assert(type(k)=='string','JSON key');out[#out+1]=enc(k)..':'..enc(y,k) end
  return '{'..table.concat(out,',')..'}'
 end
 return enc(v)
end
return M
