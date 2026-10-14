#!/usr/bin/env python3
"""Isolated real OpenSSL public metadata; no device or public operations."""
import pathlib, subprocess, tempfile
ROOT=pathlib.Path(__file__).resolve().parents[2]
LUA='/home/eric/homestun-sdk-check/local-tools/usr/bin/lua5.1'
with tempfile.TemporaryDirectory(prefix='hp-san-',dir='/home/eric/homestun-sdk-check') as td:
 p=pathlib.Path(td)
 subprocess.run(['openssl','req','-x509','-newkey','rsa:2048','-nodes','-days','2','-subj','/CN=not-a-san.example','-addext','subjectAltName=DNS:*.example.test,DNS:example.test,DNS:xn--bcher-kva.example','-keyout',str(p/'key.pem'),'-out',str(p/'cert.pem')],check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
 code="""package.path=arg[1]..'/homepublish/files/usr/share/homepublish/?.lua;'..package.path
local C=require('certificate-metadata');local m,e=C.read(arg[2]);assert(m,e)
assert(m.status=='valid' and #m.sans==3 and m.not_after and m.not_before)
assert(C.match(m.sans,'photos.example.test')=='wildcard')
assert(C.match(m.sans,'example.test')=='exact')
assert(not C.match(m.sans,'a.b.example.test'))
assert(not C.match(m.sans,'not-a-san.example'))
local j=require('product-json').encode(m);assert(not j:find('BEGIN',1,true) and not j:find('key.pem',1,true))
assert(not C.read('/arbitrary path.pem'))
print('PASS actual OpenSSL SAN/validity metadata, no CN fallback, no key/path disclosure')
"""
 (p/'test.lua').write_text(code)
 subprocess.run([LUA,str(p/'test.lua'),str(ROOT),str(p/'cert.pem')],check=True)
