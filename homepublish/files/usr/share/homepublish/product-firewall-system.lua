-- SPDX-License-Identifier: Apache-2.0
-- Fixed root-only transport to a short-lived worker serialized with fw4's flock.
-- nixio file:lock uses lockf(), NOT flock(); it cannot serialize against fw4.
local J=require('product-json');local M={};local sequence=0
local ROOT='/var/run/homepublish-firewall'
function M.identity(pid)
 local f=io.open('/proc/'..pid..'/stat');if not f then return nil end
 local s=f:read('*a');f:close();local rest=s and s:match('^%d+ %b() (.*)');local n=0
 if not rest or rest:match('^[ZX] ') then return nil end
 for value in (rest or ''):gmatch('%S+') do n=n+1;if n==20 then return value end end
end
function M.reconcile(rules,lease)
 if os.execute('timeout 1 flock -xn /dev/null /bin/true >/dev/null 2>&1')~=0 then return false,'firewall timeout/flock capability unavailable' end
 local n=require('nixio');local fs=require('nixio.fs')
 fs.mkdir(ROOT,'700');local st=fs.lstat(ROOT)
 if not st or st.type~='dir' or st.uid~=0 or not fs.chmod(ROOT,'700') then return false,'firewall runtime directory unsafe' end
 sequence=sequence+1;local pid=n.getpid();local directory=ROOT..'/'..pid..'-'..sequence
 if not fs.mkdir(directory,'700') then return false,'firewall request directory failed' end
 local function clean()fs.unlink(directory..'/request.json');fs.unlink(directory..'/batch.nft');fs.unlink(directory..'/result.json');fs.rmdir(directory)end
 local identity=M.identity(pid)
 if not identity then clean();return false,'firewall controller identity unavailable' end
 local f=io.open(directory..'/request.json','w')
 if not f then clean();return false,'firewall request write failed' end
 local written=f:write(J.encode({rules=rules,lease=lease,pid=pid,identity=identity,uptime=n.sysinfo().uptime}));local closed=f:close()
 if not written or not closed then clean();return false,'firewall request write failed' end
 -- timeout bounds lock contention and nft execution; request age/identity are
 -- checked again under the lock. No worker is a persistent recovery authority.
 local code=os.execute('timeout 5 flock -x /var/run/fw4.lock /usr/bin/lua /usr/share/homepublish/product-firewall-apply.lua '..directory..' >/dev/null 2>&1')
 local result=io.open(directory..'/result.json');local bytes=result and result:read('*a');if result then result:close() end
 local ok,r=pcall(J.decode,bytes or '');clean()
 if code~=0 or not ok or type(r)~='table' or r.ok~=true then return false,ok and type(r)=='table' and r.error or 'firewall worker unavailable' end
 return true
end
return M
