-- SPDX-License-Identifier: Apache-2.0
-- System lifecycle only; fixed provider and compiled persistent store.
local source=debug.getinfo(1,'S').source:sub(2):match('^(.*)/')
package.path=source..'/?.lua;'..package.path
local P=require('product-provider')
local W=require('product-wire')
local function run()
 assert(#arg==1,'fixed lifecycle action required')
 local s
 if arg[1]=='status' then s=assert(P.handle({action='status'}))
 elseif arg[1]=='stop' then
  s=require('product-controller').new(require('product-system-provider')).stop()
 elseif arg[1]=='start' then
  s=assert(P.handle({action='status'}))
  -- No daemon or legacy lease is launched while production activation is gated.
  assert(s.desired_state.state=='disabled','production provider unavailable')
 else error('unsupported lifecycle action') end
 io.write(W.encode(s),'\n')
end
local ok=pcall(run)
if not ok then io.stderr:write('Lifecycle unavailable; production activation remains disabled\n');os.exit(1) end
