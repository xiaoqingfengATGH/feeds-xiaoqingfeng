-- SPDX-License-Identifier: Apache-2.0
-- Fixed production instance; internal factory is never selected by RPC input.
local core=assert(loadfile('/usr/share/homepublish/product-store-core.lua'))()
return core.new('/etc/homepublish/product')
