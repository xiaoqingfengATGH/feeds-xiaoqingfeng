#!/usr/bin/env python3
"""Real OpenSSL SAN/validity contracts; private target Lua runtime."""
code = "package.path=arg[1]..'/homepublish/files/usr/share/homepublish/?.lua;'..package.path\nlocal C=require('certificate-metadata');local m,e=C.read(arg[2]);assert(m,e)\nassert(m.status=='within_validity' and m.tls_validated==false and #m.sans==3 and m.not_after and m.not_before)\nassert(C.validity('Jan  1 00:00:00 2030 GMT','Jan  2 00:00:00 2030 GMT',0)=='not_yet_valid')\nassert(C.validity('Jan  1 00:00:00 1970 GMT','Jan  2 00:00:00 1970 GMT',86400)=='expired')\nassert(C.match(m.sans,'photos.example.test')=='wildcard')\nassert(C.match(m.sans,'example.test')=='exact')\nassert(not C.match(m.sans,'a.b.example.test'))\nassert(not C.match(m.sans,'not-a-san.example'))\nlocal j=require('product-json').encode(m);assert(not j:find('BEGIN',1,true) and not j:find('key.pem',1,true))\nassert(not C.read('/arbitrary path.pem'))\nprint('PASS actual OpenSSL SAN/validity metadata, no CN fallback, no key/path disclosure')\n"

if __name__ == '__main__':
    import runpy
    from pathlib import Path
    runpy.run_path(str(Path(__file__).with_name('run-device-retained-contracts.py')), run_name='__main__')
