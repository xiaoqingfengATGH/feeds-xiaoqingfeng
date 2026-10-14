-- SPDX-License-Identifier: Apache-2.0
assert(#arg==0,'no arguments')
package.path='/usr/share/homepublish/?.lua;'..package.path
local J=require('product-json')
local r=J.decode(io.stdin:read(262145));assert(type(r)=='table','request')
io.write(require('product-channel').request(J.encode(r)),'\n')
