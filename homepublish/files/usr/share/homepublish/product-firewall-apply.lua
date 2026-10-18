-- SPDX-License-Identifier: Apache-2.0
-- Internal only: always run through flock -x /var/run/fw4.lock by the adapter.
package.path='/usr/share/homepublish/?.lua;'..package.path
local J=require('product-json');local NJ=require('luci.jsonc');local n=require('nixio');local fs=require('nixio.fs')
local directory=arg[1]
assert(#arg==1 and type(directory)=='string' and directory:match('^/var/run/homepublish%-firewall/%d+%-%d+$'),'fixed worker path required')
local st=fs.lstat(directory);assert(st and st.type=='dir' and st.uid==0 and st.modedec==700,'unsafe request directory')
local function read(path)local f=io.open(path);if not f then return nil end;local s=f:read('*a');f:close();return s end
local function capture(command)
 local f=io.popen(command.." 2>/dev/null && printf '\\nHOMEPUBLISH_OK\\n'");if not f then return nil end
 local s=f:read('*a');f:close();return s and s:match('^(.*)\nHOMEPUBLISH_OK\n$')
end
local request=J.decode(assert(read(directory..'/request.json')))
local function authorized()
 return type(request.pid)=='number' and request.pid==math.floor(request.pid) and request.pid>1
  and require('product-firewall-system').identity(request.pid)==request.identity
  and type(request.uptime)=='number' and n.sysinfo().uptime>=request.uptime and n.sysinfo().uptime-request.uptime<=5
end
local function snapshot()
 local tables=capture('nft -j list tables');if not tables then return nil end
 local ok,t=pcall(NJ.parse,tables);if not ok or type(t)~='table' or type(t.nftables)~='table' then return nil end
 local exists=false;for _,entry in ipairs(t.nftables) do if entry.table and entry.table.family=='inet' and entry.table.name=='fw4' then exists=true end end
 if not exists then return {nftables={}} end
 local bytes=capture('nft -j list table inet fw4');if not bytes then return nil end
 -- jsonc discards null object members; retain ACCEPT for exact expression verification.
 bytes=bytes:gsub('"accept"%s*:%s*null','"accept":{}')
 local valid,r=pcall(NJ.parse,bytes);return valid and r or nil
end
local F=require('product-firewall').new({snapshot=snapshot,
 bootstrap=fs.stat('/usr/share/nftables.d/table-post/90-homepublish.nft','type')=='reg',
 apply=function(batch)
 if not authorized() then return false end
 local f=io.open(directory..'/batch.nft','w');if not f then return false end
 local written=f:write(batch);local closed=f:close();if not written or not closed then return false end
 return os.execute('nft -f '..directory..'/batch.nft >/dev/null 2>&1')==0
end})
local ok,err
if authorized() then ok,err=F.reconcile(request.rules,request.lease) else ok=false;err='firewall controller lease stale' end
-- A read-back under the same fw4 lock distinguishes commit from status failure.
if ok then
 local live=snapshot()
 if not require('product-firewall').verify(request.rules,live,request.lease) then ok=false;err='firewall verification failed' end
end
local f=assert(io.open(directory..'/result.json','w'));assert(f:write(J.encode({ok=ok==true,error=err})));assert(f:close())
os.exit(ok and 0 or 1)
