local root=assert(arg[1]);local runtime=assert(arg[2]);package.path=root..'/?.lua;'..package.path
local fs=require('nixio.fs');local n=require('nixio');local J=require('product-json')
local R=require('product-restart')
local state={intent_revision=5,active_revision=2,desired_state={state='enabled',manual_stop_latch=false},runtime={generation=5,expires_at=os.time()+200}}
local function read()local f=assert(io.open(runtime..'/restart'));local b=f:read('*a');f:close();return J.decode(b)end
local function write(t)local f=assert(io.open(runtime..'/restart','w'));f:write(J.encode(t));f:close();assert(fs.chmod(runtime..'/restart','600'))end
assert(R.prepare(state));assert(fs.lstat(runtime).modedec==700 and fs.lstat(runtime..'/restart').modedec==600,'private marker')
assert(not R.consume(state),'live owner/unarmed marker must not authorize restart');assert(not fs.lstat(runtime..'/restart'),'single use invalid too')
local function dead_marker()assert(R.prepare(state));local t=read();t.pid=4194304;t.ready=true;write(t);return t end
local t=dead_marker();assert(R.consume(state),'fresh same boot dead owner accepted');assert(not R.consume(state),'single use')
t=dead_marker();t.boot='different';write(t);assert(not R.consume(state),'other boot rejected')
t=dead_marker();t.uptime=t.uptime-31;write(t);assert(not R.consume(state),'stale rejected')
t=dead_marker();t.uptime=t.uptime+100;write(t);assert(not R.consume(state),'future rejected')
t=dead_marker();state.intent_revision=6;assert(not R.consume(state),'changed intent rejected');state.intent_revision=5
t=dead_marker();fs.chmod(runtime..'/restart','644');assert(not R.consume(state),'public marker rejected')
t=dead_marker();local target=runtime..'/target';assert(fs.rename(runtime..'/restart',target));assert(fs.symlink(target,runtime..'/restart'));assert(not R.consume(state),'symlink rejected');assert(fs.lstat(target),'symlink target not removed');fs.unlink(target)
assert(R.prepare(state));t=read();t.pid=4194304;write(t);assert(R.wait(),'dead old daemon permits arm');assert(R.consume(state),'wait arms one restart')
-- A failed/asynchronous kill must not arm, remove an old socket, or start.
local socket=assert(n.socket('unix','stream'));assert(socket:bind(runtime..'/control.sock'));assert(socket:listen(1))
assert(R.prepare(state));local began=os.time();assert(not R.wait(),'live old daemon wait must fail closed')
assert(os.time()-began<=15 and not fs.lstat(runtime..'/restart'),'bounded wait clears abandoned marker')
assert(fs.lstat(runtime..'/control.sock'),'live old socket retained');socket:close();fs.unlink(runtime..'/control.sock')
assert(R.prepare(state));t=read();t.pid=4194304;write(t);local other=runtime..'/link';assert(fs.link(runtime..'/restart',other));assert(not R.consume(state),'hardlinked marker rejected');fs.unlink(other)
R.clear();assert(not fs.lstat(runtime..'/restart'));assert(fs.rmdir(runtime))
print('RESTART_MARKER_GREEN')
