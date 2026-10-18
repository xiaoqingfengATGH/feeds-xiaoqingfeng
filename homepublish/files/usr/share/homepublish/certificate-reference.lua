-- SPDX-License-Identifier: Apache-2.0
-- References are opaque identities, never paths or shell patterns. ACME keeps
-- a literal leading '*.' in wildcard certificate directory names.
local M={}
function M.parse(ref)
 if type(ref)~='string' then return nil end
 local provider,id=ref:match('^(%a+):(.+)$')
 if provider~='acme' and provider~='import' then return nil end
 if id:sub(1,2)=='*.' then
  if provider~='acme' or #id>258 then return nil end
  local domain=id:sub(3):gsub('_ecc$',''):gsub('_rsa$','')
  if #domain==0 or #domain>253 or domain:find('[^a-z0-9.%-]') or domain:find('..',1,true) or domain:sub(-1)=='.' then return nil end
  for label in domain:gmatch('[^.]+') do
   if #label>63 or not label:match('^[a-z0-9]') or not label:match('[a-z0-9]$') then return nil end
  end
  if domain:sub(1,1)=='.' then return nil end
 elseif #id>64 or not id:match('^[a-zA-Z0-9_][a-zA-Z0-9_.%-]*$') or id:find('..',1,true) then return nil end
 return provider,id
end
return M
