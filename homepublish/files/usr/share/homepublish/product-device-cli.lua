-- SPDX-License-Identifier: Apache-2.0
-- Root-local device-test acceptance, not rpcd/public activation.
assert(#arg==0,'no paths or commands')
package.path='/usr/share/homepublish/?.lua;'..package.path
local J=require('product-json');local W=require('product-wire')
local r=J.decode(io.stdin:read(262145));assert(type(r)=='table','request')
local response=require('homepublish_device').request(W.encode(r))
io.write(J.encode(W.decode(response)),'\n')
