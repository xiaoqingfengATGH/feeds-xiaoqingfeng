-- SPDX-License-Identifier: Apache-2.0
local n=require('nixio')
local fs=require('nixio.fs')
local M={}
local MAX_STATE_BYTES=262144
function M.new(root)
 assert(type(root)=='string' and root:sub(1,1)=='/' and not root:find('/%.%./'),'invalid internal root')
 local function transaction(callback)
  local lock,owned_candidate
  local failure='store failure'
  local function check(ok,message)
   if not ok then failure=message or 'store failure';error(failure,0) end
   return ok
  end
  local function run()
   local st=fs.lstat(root)
   if not st then assert(fs.mkdir(root,'700'),'store directory create failed');st=assert(fs.lstat(root)) end
   check(st.type=='dir' and st.uid==0 and st.modedec==700,'unsafe store directory')
   local function checked(path)
    local st,code=fs.lstat(path)
    if not st then assert(code==2,'store path stat failed');return nil end
    check(st.type=='reg' and st.uid==0 and st.modedec==600,
     path==root..'/lock' and 'unsafe store lock' or path==root..'/state' and 'unsafe store state' or path==root..'/candidate' and 'unsafe store candidate' or 'migration backup failed')
    return st
   end
   checked(root..'/lock')
   lock=assert(n.open(root..'/lock','a+','600'),'store lock open failed')
   check(lock:lock('tlock'),'store busy')
   local old
   local state=checked(root..'/state')
   if state then
    check(state.size>0 and state.size<=MAX_STATE_BYTES,'unsafe store state')
    local f=assert(io.open(root..'/state','rb'),'store state read failed')
    old=f:read('*a');local closed=f:close()
    check(closed and old and #old==state.size,'unsafe store state')
   end
   local callback_ok,bytes,response,backup=pcall(callback,old)
   if not callback_ok then check(false,'invalid stored state or request') end
   check(backup==nil or type(backup)=='boolean','invalid migration backup request')
   if bytes~=nil then
    assert(type(bytes)=='string' and #bytes>0 and #bytes<=MAX_STATE_BYTES,'invalid store bytes')
    local prior_candidate=checked(root..'/candidate')
    if prior_candidate then assert(fs.unlink(root..'/candidate'),'candidate cleanup failed') end
    local out=assert(n.open(root..'/candidate',n.open_flags('wronly','creat','excl'),'600'))
    owned_candidate=true
    local ok,err=pcall(function() assert(out:write(bytes)==#bytes);assert(out:sync()) end)
    local closed=out:close()
    if not ok or not closed then fs.unlink(root..'/candidate');error('candidate write failed') end
    if backup then
     assert(old,'migration requires original state')
     local path=root..'/migration-v1'
     local prior=checked(path)
     if prior then
      local f=assert(io.open(path,'rb'));local data=f:read('*a');local closed=f:close()
      check(closed and data==old,'migration backup failed')
     else
      local f=assert(n.open(path,n.open_flags('wronly','creat','excl'),'600'))
      local ok,err=pcall(function() assert(f:write(old)==#old);assert(f:sync()) end)
      local closed=f:close()
      if not ok or not closed then fs.unlink(path);check(false,'migration backup failed') end
     end
    end
    assert(fs.rename(root..'/candidate',root..'/state'))
    owned_candidate=false
   end
   return response
  end
  local ok,result=pcall(run)
  if owned_candidate then fs.unlink(root..'/candidate') end
  if lock then lock:close() end
  -- Only frozen public vocabulary escapes; never expose Lua locations or OS errors.
  if not ok then return nil,failure end
  return result
 end
 return {transaction=transaction,migration_backup=true}
end
return M
