-- SPDX-License-Identifier: Apache-2.0
local root='/root/homepublish-lua-store/p1'
local store=dofile(root..'/device-p1-lua-scope.lua').store
local fs=require('nixio.fs')
local mode=os.getenv('HP_BACKUP_FAIL')
if mode then
 assert(mode=='write' or mode=='sync' or mode=='close','unknown fault')
 local n=require('nixio');local original_open=n.open
 n.open=function(path,...)
  local fd=assert(original_open(path,...))
  if path~=root..'/store/migration-v1' then return fd end
  return {
   write=function(_,bytes) if mode=='write' then return nil,5 end;return fd:write(bytes) end,
   sync=function() if mode=='sync' then return nil,5 end;return fd:sync() end,
   close=function() local ok=fd:close();if mode=='close' then return nil,5 end;return ok end
  }
 end
end
local original=' {"state_version":1,"legacy":"exact bytes"}\n\000tail'
local updated='{"state_version":1,"saved":{"schema_version":2}}\n'
local function read(name) local f=io.open(root..'/store/'..name,'rb');if not f then return nil end local s=f:read('*a');f:close();return s end
local function put(name,s) local f=assert(io.open(root..'/store/'..name,'wb'));assert(f:write(s));assert(f:close());assert(fs.chmod(root..'/store/'..name,'600')) end
assert(store.transaction(function(old) assert(old==nil);return original,{legacy=true} end).legacy)
if arg[1]=='fault' then
 local mode=assert(os.getenv('HP_BACKUP_FAIL'))
 local equal=arg[2]=='equal'
 if equal then put('migration-v1',original) end
 local before=equal and fs.stat(root..'/store/migration-v1').ino
 local r,e=store.transaction(function(old) assert(old==original);return updated,{},true end)
 assert(r==nil and e=='migration backup failed',tostring(e))
 assert(read('state')==original and not fs.lstat(root..'/store/candidate'),'fault changed state or leaked candidate')
 if equal then assert(read('migration-v1')==original and fs.stat(root..'/store/migration-v1').ino==before,'fault removed preexisting backup')
 else assert(not fs.lstat(root..'/store/migration-v1'),'partial backup leaked') end
 print('PASS injected '..mode..' old state preserved, candidate absent, backup '..(equal and 'preserved' or 'absent'))
 return
end
local response,err=store.transaction(function(old) assert(old==original);return updated,{migrated=true},true end)
assert(response and response.migrated,err)
assert(read('migration-v1')==original,'missing exact original-journal backup')
local st=assert(fs.stat(root..'/store/migration-v1'))
assert(st.modedec==600 and st.uid==0 and st.nlink==1 and st.type=='reg','unsafe backup metadata')
assert(store.transaction(function(old) assert(old==updated);return nil,old end)==updated)
assert(store.migration_backup==true,'missing migration_backup capability')
print('PASS exact original bytes, private mode, updated readback, legacy two-return callback, capability')
local function path(name) return root..'/store/'..name end
local function reset()
 for _,name in ipairs({'migration-v1','candidate','state','other'}) do if fs.lstat(path(name)) then assert(fs.unlink(path(name))) end end
 put('state',original)
end
local function migrate() return store.transaction(function(old) assert(old==original);return updated,'response-only',true end) end
local function blocked(label)
 local r,e=migrate();assert(r==nil and type(e)=='string',label..' accepted')
 assert(read('state')==original,label..' changed old state')
 assert(not fs.lstat(path('candidate')),label..' leaked candidate')
 print('PASS '..label..' fail closed')
end
reset();put('migration-v1',original)
local ino=fs.stat(path('migration-v1')).ino
assert(migrate()=='response-only');assert(read('state')==updated and read('migration-v1')==original)
assert(fs.stat(path('migration-v1')).ino==ino,'equal backup was overwritten')
print('PASS equal backup reuse keeps inode and response-only API')
reset();put('migration-v1','foreign unequal');blocked('unequal backup');assert(read('migration-v1')=='foreign unequal')
reset();local unequal=string.rep('x',#original);put('migration-v1',unequal);blocked('same-length unequal backup');assert(read('migration-v1')==unequal)
reset();put('migration-v1',original);assert(fs.chmod(path('migration-v1'),'4600'));blocked('special mode bits');assert(fs.stat(path('migration-v1')).modedec==4600)
reset();put('other','foreign target');assert(fs.symlink(path('other'),path('migration-v1')))
blocked('symlink backup');assert(fs.readlink(path('migration-v1'))==path('other') and read('other')=='foreign target')
reset();put('migration-v1',original);assert(fs.chmod(path('migration-v1'),'644'));blocked('foreign mode');assert(fs.stat(path('migration-v1')).modedec==644)
reset();put('migration-v1',original);assert(fs.chown(path('migration-v1'),65534,65534));blocked('foreign owner');assert(fs.stat(path('migration-v1')).uid==65534)
reset();put('migration-v1',original);assert(fs.link(path('migration-v1'),path('other')));blocked('multiple hardlinks');assert(read('other')==original)
reset();assert(fs.mkfifo(path('migration-v1'),'600'));blocked('FIFO backup');assert(fs.lstat(path('migration-v1')).type=='fifo')
reset();assert(fs.mkdir(path('migration-v1'),'700'));blocked('directory backup');assert(fs.rmdir(path('migration-v1')))
reset();assert(fs.unlink(path('state')));local r,e=store.transaction(function(old) assert(old==nil);return updated,{},true end)
assert(r==nil and e and not read('state') and not fs.lstat(path('migration-v1')) and not fs.lstat(path('candidate')))
print('PASS missing original rejects migration')
reset();assert(store.transaction(function() return nil,'read-only',true end)=='read-only');assert(not fs.lstat(path('migration-v1')))
assert(store.transaction(function() return updated,'false flag',false end)=='false flag');assert(not fs.lstat(path('migration-v1')))
print('PASS read-only true and write false do not create backup')
for _,flag in ipairs({'true',1,{}}) do
 reset();local r,e=store.transaction(function()return updated,'bad',flag end)
 assert(r==nil and e and read('state')==original and not fs.lstat(path('migration-v1')))
end
print('PASS third return type guarded')
reset();put('migration-v1',original);assert(fs.symlink(path('other'),path('candidate')))
local r,e=migrate();assert(r==nil and e and read('state')==original and read('migration-v1')==original)
assert(fs.lstat(path('candidate')).type=='lnk');assert(fs.unlink(path('candidate')))
print('PASS safe preexisting backup survives later failure')
print('TOTAL backup device assertions PASS')
