-- SPDX-License-Identifier: Apache-2.0
local fs=require('nixio.fs')
local base='/root/homepublish-lua-store'
local case=assert(arg[1])
local root=base..'/test-'..case
assert(not fs.lstat(root),'test root already exists: '..root)
assert(fs.mkdir(root,'700'))
local core=assert(loadfile(base..'/source/product-store-core.lua'))()
local s=core.new(root)
assert(s.migration_backup==true)
local called=false
local result,err=s.transaction(function(old)
 assert(old==nil);called=true;return 'original',false
end)
assert(called and result==false and err==nil,'false response / initial write: '..tostring(err))
local function read() local f=assert(io.open(root..'/state','rb'));local b=f:read('*a');f:close();return b end
assert(read()=='original')
local before=fs.stat(root..'/state').mtime
assert(s.transaction(function(old) assert(old=='original');return nil,'read' end)=='read')
assert(fs.stat(root..'/state').mtime==before)
print('CONTRACT_GREEN')
if case:match('classification') then
 -- Run the actual CLI/provider/wire bytes, selecting only an internal store
 -- instance in this child process; never evaluate the production wrapper.
 local wrapper=root..'/cli.lua'
 local f=assert(io.open(wrapper,'w'))
 f:write("local original=dofile;dofile=function(path) if path=='"..base.."/source/product-store.lua' then return original('"..base.."/source/product-store-core.lua').new('"..root.."') end return original(path) end;dofile('"..base.."/source/product-cli.lua')")
 f:close()
 local wire=dofile(base..'/source/product-wire.lua')
 local input=root..'/request';f=assert(io.open(input,'w'));f:write(wire.encode({action='migration_preview'}));f:close()
 local output=root..'/response'
 assert(os.execute('lua '..wrapper..' < '..input..' > '..output)==256)
 f=assert(io.open(output));local raw=f:read('*a');f:close()
 local response=wire.decode((raw:gsub('\n$','')))
 print('CLI_CORRUPT_STATE='..raw)
 assert(response.error_code=='STATE_UNKNOWN' and response.field=='state' and response.retryable==true,'CLI misclassified corrupted store')
 local r,e=s.transaction(function() error('callback private detail') end)
 assert(r==nil and e=='invalid stored state or request','callback error vocabulary: '..tostring(e))
 print('CLASSIFICATION_GREEN')
end
if case:match('faults') then
 local n=require('nixio')
 local original_rename=fs.rename
 fs.rename=function() return nil,5,'injected rename error' end
 local r,e=s.transaction(function() return 'new','bad' end)
 fs.rename=original_rename
 assert(r==nil and e and read()=='original' and not fs.lstat(root..'/candidate'))
 local original_open=n.open
 for _,fault in ipairs({'write','sync','close'}) do
  n.open=function(path,...)
   local fd=assert(original_open(path,...))
   if path~=root..'/candidate' then return fd end
   return {
    write=function(_,data) if fault=='write' then return nil,5 end;return fd:write(data) end,
    sync=function() if fault=='sync' then return nil,5 end;return fd:sync() end,
    close=function() local ok=fd:close();if fault=='close' then return nil,5 end;return ok end
   }
  end
  local r,e=s.transaction(function() return 'new','bad' end)
  n.open=original_open
  assert(r==nil and e and read()=='original' and not fs.lstat(root..'/candidate'),fault..' failure not isolated')
  assert(s.transaction(function() return nil,'released' end)=='released')
 end
 print('FAULTS_GREEN')
end
if case:match('cleanup') then
 assert(fs.mkdir(root..'/migration-v1','700'))
 local r,e=s.transaction(function() return 'new','bad',true end)
 assert(r==nil and e and read()=='original')
 assert(not fs.lstat(root..'/candidate'),'failed backup leaked candidate')
 assert(fs.rmdir(root..'/migration-v1'))
 print('CLEANUP_GREEN')
end
if case:match('resources') then
 assert(fs.symlink(root..'/state',root..'/candidate'))
 local r,e=s.transaction(function() return 'damage','bad' end)
 assert(r==nil and e and read()=='original','candidate symlink accepted')
 assert(fs.lstat(root..'/candidate').type=='lnk');assert(fs.unlink(root..'/candidate'))
 local function countfd() local count=0;for _ in fs.dir('/proc/self/fd') do count=count+1 end;return count end
 local before=countfd()
 for i=1,150 do
  local r,e=s.transaction(function() error('callback failure') end);assert(r==nil and e)
  assert(s.transaction(function() return nil,'released' end)=='released')
 end
 assert(countfd()==before,'descriptor leak')
 local n=require('nixio');local fd=assert(n.open(root..'/lock','r+'));assert(fd:lock('tlock'))
 local child=root..'/child.lua';local f=assert(io.open(child,'w'))
 f:write("local c=dofile('/root/homepublish-lua-store/source/product-store-core.lua');local r,e=c.new('"..root.."').transaction(function() error('must not call') end);assert(r==nil and e:find('store busy'));print('TWO_PROCESS_BUSY_GREEN')")
 f:close();assert(os.execute('lua '..child)==0);assert(fd:close())
 assert(s.transaction(function() return nil,'released' end)=='released')
 print('RESOURCES_GREEN')
end
if case:match('migration') then
 assert(s.transaction(function(old) assert(old=='original');return 'v2','saved',true end)=='saved')
 local f=assert(io.open(root..'/migration-v1','rb'));assert(f:read('*a')=='original');f:close()
 assert(fs.lstat(root..'/migration-v1').modedec==600)
 local r,e=s.transaction(function() return 'v3','bad',true end)
 assert(r==nil and e and read()=='v2','conflicting backup accepted')
 assert(s.transaction(function() return 'original','reset' end)=='reset')
 assert(s.transaction(function() return 'v2','reuse',true end)=='reuse')
 assert(s.transaction(function() return 'original','restore-test-baseline' end)=='restore-test-baseline')
 print('MIGRATION_GREEN')
end
if case:match('safety') then
 local function reject_path(name,setup)
  local dir=root..'/'..name;assert(fs.mkdir(dir,'700'));setup(dir)
  local invoked=false
  local r,e=core.new(dir).transaction(function() invoked=true;return 'damage','bad' end)
  assert(r==nil and e and not invoked,'unsafe path accepted: '..name)
 end
 reject_path('state-link',function(d) assert(fs.symlink(root..'/state',d..'/state')) end)
 reject_path('lock-link',function(d) assert(fs.symlink(root..'/lock',d..'/lock')) end)
 reject_path('state-empty',function(d) local f=assert(io.open(d..'/state','w'));f:close();assert(fs.chmod(d..'/state','600')) end)
 reject_path('state-dir',function(d) assert(fs.mkdir(d..'/state','700')) end)
 reject_path('state-large',function(d) local f=assert(io.open(d..'/state','w'));f:write(string.rep('x',262145));f:close();assert(fs.chmod(d..'/state','600')) end)
 assert(read()=='original')
 print('SAFETY_GREEN')
end
if case:match('validation') then
 local function rejected(bytes,backup)
  local r,e=s.transaction(function() return bytes,'bad',backup end)
  assert(r==nil and type(e)=='string','invalid write accepted')
  assert(read()=='original','old bytes overwritten')
 end
 rejected('');rejected(7);rejected(string.rep('x',262145));rejected('new','yes')
 local r,e=s.transaction(function() error('bad stored JSON') end)
 assert(r==nil and e and read()=='original')
 assert(s.transaction(function() return string.rep('x',262144),'limit' end)=='limit')
 assert(#read()==262144)
 print('VALIDATION_GREEN')
end
