#!/usr/bin/env python3
"""Fixed lifecycle CLI against a real isolated native journal; not procd acceptance."""
import json, os, pathlib, subprocess, tempfile
ROOT=pathlib.Path(__file__).resolve().parents[2]
BASE=pathlib.Path('/home/eric/homestun-sdk-check')
LUA=str(BASE/'local-tools/usr/bin/lua5.1')
DEV=BASE/'canonical-lua-dev/usr/include'
with tempfile.TemporaryDirectory(prefix='lifecycle-product-',dir=BASE) as td:
 d=pathlib.Path(td)
 subprocess.run(['cc','-std=c99','-Wall','-Wextra','-Werror','-Wno-misleading-indentation','-shared','-fPIC','-I'+str(DEV/'lua5.1'),'-I'+str(DEV/'x86_64-linux-gnu'),'-DPRODUCT_ROOT='+json.dumps(str(d/'store')),str(ROOT/'homepublish/src/product-store.c'),'-o',str(d/'homepublish_store.so')],check=True)
 env={**os.environ,'LUA_CPATH':str(d/'?.so')}
 cli=ROOT/'homepublish/files/usr/share/homepublish/product-lifecycle.lua'
 assert cli.is_file(),'fixed product lifecycle missing'
 def run(action,rc=0):
  r=subprocess.run([LUA,str(cli),action],env=env,text=True,capture_output=True)
  assert r.returncode==rc,(action,r.returncode,r.stdout,r.stderr)
  return r.stdout
 assert 'disabled' in run('status')
 assert 'disabled' in run('start')
 assert 'manual_stop_latchb1' in run('stop')
 assert 'manual_stop_latchb1' in run('status')
 run('arbitrary-command',1)
 init=(ROOT/'homepublish/files/etc/init.d/homepublish').read_text()
 assert 'product-device-cli.lua' in init and 'stop_service()' in init and 'status_service()' in init,'init not bridged to product lifecycle'
 assert 'natmap' not in init and '--provision' not in init,'legacy exposure path still reachable'
 print('PASS fixed lifecycle persisted status/disabled start/controller Stop latch; no production activation')
