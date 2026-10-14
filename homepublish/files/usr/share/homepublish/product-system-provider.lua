-- SPDX-License-Identifier: Apache-2.0
-- Fixed production dependency. No test adapters or client-selected executables.
-- Data-plane production authority is unavailable; never claim historical cleanup.
local P=require('product-provider')
local M={}
function M.stop()
 local s=assert(P.handle({action='status'}))
 return s.active_revision==nil and s.attempted_revision==nil
end
function M.plan() return nil,'production provider unavailable' end
function M.start() return false end
function M.readiness() return false end
function M.renew() return false end
return M
