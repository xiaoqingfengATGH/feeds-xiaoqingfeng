-- SPDX-License-Identifier: Apache-2.0
-- Run only on the authorized OpenWrt device, against a private root.
local n=require('nixio')
local fs=require('nixio.fs')
local root=assert(arg[1],'private probe root required')
assert(root:match('^/root/homepublish%-lua%-store/capabilities[%w%-]*$'),'unsafe probe root')
assert(fs.mkdir(root,'700') or fs.stat(root,'type')=='dir')
local function child(body)
 local path=root..'/child.lua'
 local f=assert(io.open(path,'w'));assert(f:write(body));assert(f:close())
 assert(os.execute('/usr/bin/lua '..path)==0,'child failed')
end
local lockpath=root..'/lock'
local lock=assert(n.open(lockpath,'w','600'))
assert(lock:lock('tlock'))
child("local n=require('nixio');local f=assert(n.open('"..lockpath.."','r+'));local ok,e=f:lock('tlock');assert(not ok and e==11);assert(f:close());print('CHILD_BUSY_GREEN')")
assert(lock:close())
child("local n=require('nixio');local f=assert(n.open('"..lockpath.."','r+'));assert(f:lock('tlock'));print('CHILD_EXIT_LOCK_HELD')")
lock=assert(n.open(lockpath,'r+'));assert(lock:lock('tlock'));assert(lock:close());print('EXIT_RELEASE_GREEN')
local function write(path,data)
 local f=assert(n.open(path,'w','600'));assert(f:write(data)==#data);assert(f:sync());assert(f:close())
end
write(root..'/state','old-complete')
write(root..'/candidate','new-complete')
assert(fs.rename(root..'/candidate',root..'/state'))
local f=assert(n.open(root..'/state','r'));assert(f:read(100)=='new-complete');assert(f:close())
assert(fs.lstat(root..'/state').modestr=='rw-------')
print('RENAME_PERMISSIONS_GREEN')
-- A real concurrent reader must never observe a truncated/intermediate value.
local old=string.rep('A',65536)
local new=string.rep('B',65536)
write(root..'/atomic-state',old)
local reader=root..'/reader.lua'
local f=assert(io.open(reader,'w'))
assert(f:write("local root='"..root.."';local a=string.rep('A',65536);local b=string.rep('B',65536);local ready=assert(io.open(root..'/reader-ready','w'));ready:write('ready');ready:close();for i=1,3000 do local f=assert(io.open(root..'/atomic-state','rb'));local s=f:read('*a');assert(f:close());assert(s==a or s==b,'partial rename observed') end;local f=assert(io.open(root..'/reader-done','w'));f:write('ok');f:close()"))
assert(f:close())
assert(os.execute('/usr/bin/lua '..reader..' > '..root..'/reader.log 2>&1 &')==0)
for i=1,100 do if fs.lstat(root..'/reader-ready') then break end;n.nanosleep(0,10000000) end
assert(fs.lstat(root..'/reader-ready'),'reader did not start')
for i=1,100 do
 write(root..'/atomic-candidate',i%2==0 and old or new)
 assert(fs.rename(root..'/atomic-candidate',root..'/atomic-state'))
end
for i=1,100 do if fs.lstat(root..'/reader-done') then break end;n.nanosleep(0,10000000) end
assert(fs.lstat(root..'/reader-done'),'reader failed; inspect private reader.log')
print('CONCURRENT_READER_ATOMIC_RENAME_GREEN')
print('LUA_STORE_CAPABILITIES_GREEN')
