-- SPDX-License-Identifier: Apache-2.0
-- Init-only fixed commands; no journal mutation, stop or provider access.
assert(#arg==1,'restart command required')
package.path='/usr/share/homepublish/?.lua;'..package.path
local R=require('product-restart')
local ok,result=pcall(function()
 if arg[1]=='clear' then R.clear();return true
 elseif arg[1]=='wait' then return R.wait()
 elseif arg[1]=='prepare' then
  R.clear()
  local J=require('product-json')
  local response=J.decode(require('product-channel').request(J.encode({action='prepare_restart'})))
  return response.restart_prepared==true
 end
 return false
end)
if not ok or result~=true then R.clear();io.stderr:write('HomePublish controller restart handshake failed\n');os.exit(1) end
