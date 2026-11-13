-- SPDX-License-Identifier: Apache-2.0
-- Root-local, same-boot, single-use explicit restart capability. Not an RPC path.
local n=require('nixio');local fs=require('nixio.fs');local J=require('product-json');local W=require('product-wire')
local M={};local root='/var/run/homepublish';local path=root..'/restart'
local function private(p,kind,mode)
 local s=fs.lstat(p)
 return s and s.type==kind and s.uid==0 and s.modedec==mode and (kind=='dir' or s.nlink==1) and s
end
local function readfile(p,limit)local f=io.open(p,'r');if not f then return nil end;local b=f:read(limit);f:close();return b end
local function boot()return readfile('/proc/sys/kernel/random/boot_id',128)end
local function uptime()local b=readfile('/proc/uptime',128);local up=b and tonumber(b:match('^(%S+)'));return up and math.floor(up)end
local function identity(pid)
 local b=readfile('/proc/'..pid..'/stat',4096);if not b then return nil end
 local rest=b:match('^%d+ %(.+%) (.+)$');if not rest then return nil end
 local a={};for v in rest:gmatch('%S+')do a[#a+1]=v end
 if a[1]=='Z' then return nil end
 return a[20]
end
local function snapshot(s)
 return W.encode({intent_revision=s.intent_revision,active_revision=s.active_revision,desired_state=s.desired_state,generation=s.runtime.generation,expires_at=s.runtime.expires_at})
end
function M.clear()
 if private(root,'dir',700) then fs.unlink(path);fs.unlink(path..'.new') end
end
local function write(t)
 assert(private(root,'dir',700),'unsafe restart directory')
 fs.unlink(path..'.new')
 local f=assert(n.open(path..'.new',n.open_flags('wronly','creat','excl'),'600'))
 local ok=f:writeall(J.encode(t));local sync=f:sync();local closed=f:close()
 if not ok or not sync or not closed then fs.unlink(path..'.new');return false end
 return fs.rename(path..'.new',path)==true
end
function M.prepare(s)
 if not fs.lstat(root) then assert(fs.mkdir(root,'700')) end
 assert(private(root,'dir',700),'unsafe restart directory');M.clear()
 local pid=n.getpid();local start=assert(identity(pid));local up=assert(uptime());local b=assert(boot())
 return write({version=1,boot=b,uptime=up,pid=pid,start=start,snapshot=snapshot(s),ready=false})
end
local function read()
 if not private(root,'dir',700) then return nil end
 local st=private(path,'reg',600);if not st or st.size>8192 or st.size==0 then return nil end
 local b=readfile(path,8193);local ok,t=pcall(J.decode,b or '')
 if not ok or type(t)~='table' then return nil end
 local fields={version=true,boot=true,uptime=true,pid=true,start=true,snapshot=true,ready=true}
 for k in pairs(t)do if not fields[k] then return nil end end
 local up=uptime()
 if t.version~=1 or type(t.boot)~='string' or t.boot~=boot() or type(t.uptime)~='number' or not up or t.uptime>up or up-t.uptime>30 then return nil end
 if type(t.pid)~='number' or t.pid%1~=0 or t.pid<1 or t.pid>4194304 or type(t.start)~='string' or not t.start:match('^%d+$') or type(t.snapshot)~='string' or type(t.ready)~='boolean' then return nil end
 return t
end
function M.wait()
 local t=read();if not t then M.clear();return false end
 for i=1,12 do
  if identity(t.pid)~=t.start then
   -- Never unlink the socket until the captured old process has exited.
   local st=fs.lstat(root..'/control.sock')
   if st and (st.type~='sock' or st.uid~=0 or not fs.unlink(root..'/control.sock')) then M.clear();return false end
   if not read() then M.clear();return false end
   t.ready=true;return write(t)
  end
  n.nanosleep(1)
 end
 M.clear();return false
end
function M.consume(s)
 local t=read();M.clear() -- Consume on every attempt, including invalid data.
 return t~=nil and t.ready==true and identity(t.pid)~=t.start and t.snapshot==snapshot(s)
end
return M
