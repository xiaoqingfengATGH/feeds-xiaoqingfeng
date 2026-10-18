"""Explicit opt-in read-only firmware probe (no deploy or nft commit).
uv run --python 3.13 --with lupa homepublish/tests/check-input-firewall-fw4.py
"""
import json
import pathlib
import subprocess
from lupa.lua51 import LuaRuntime

SOURCE = pathlib.Path(__file__).resolve().parents[1] / 'files/usr/share/homepublish'
SSH = ['ssh', '-i', 'D:/DevPortal/CloudHosts/HomePri.key', '-p', '22',
       '-o', 'ProxyCommand=none', '-o', 'ProxyJump=none',
       '-o', 'IdentitiesOnly=yes', '-o', 'BatchMode=yes', 'root@192.168.1.2']

def remote(command, payload=b''):
    result = subprocess.run(SSH + [command], input=payload, capture_output=True, timeout=45)
    if result.returncode:
        raise RuntimeError(f'{command}: {result.returncode}: {result.stderr.decode()}')
    return result.stdout.decode()

live = json.loads(remote('nft -j list table inet fw4'))
lua = LuaRuntime(unpack_returned_tuples=True)
def table(value):
    if isinstance(value, dict): return lua.table_from({k: table(v) for k,v in value.items() if v is not None})
    if isinstance(value, list): return lua.table_from([table(v) for v in value])
    return value
lua.globals().live = table(live)
lua.globals().source = SOURCE.as_posix()
batch = lua.execute('''
package.path=source..'/?.lua;'..package.path
local batch
local F=require('product-firewall').new({bootstrap=true,snapshot=function()return live end,
 apply=function(s)batch=s;return true end})
assert(F.reconcile({{family='ipv4',zone='wan',port=62443,protocol='tcp'},
 {family='ipv6',zone='lan',port=62222,protocol='tcp'},
 {family='ipv4',zone='wan',port=62444,protocol='tcp',dest_ip='192.168.1.2'},
 {family='ipv6',zone='lan',port=62223,protocol='tcp',dest_ip='fd00::1'}}))
return batch
''')
remote('nft -c -f -', batch.encode())  # bytes: never send Windows CRLF to nft
names = ['direct-address.lua', 'product-firewall-plan.lua', 'product-firewall.lua', 'product-firewall-system.lua', 'product-firewall-apply.lua',
         'product-v2-runtime.lua', 'product-system-provider.lua', 'product-controller.lua']
compile_script = '\n'.join("assert(loadstring([====[" + (SOURCE / name).read_text(encoding='utf-8')
                           + "]====], '" + name + "'))" for name in names)
compile_script += '''
local f=assert(io.popen('nft -j list table inet fw4'))
local live=assert(require('luci.jsonc').parse(f:read('*a')));f:close()
assert(type(live.nftables)=='table');print('LIVE_NFT_JSON_PARSE_OK')
'''
parsed = remote('lua -', compile_script.encode()).strip()
print(json.dumps({'nft_check_exit': 0, 'live_lua_compile': names, 'live_nft_json': parsed,
                  'firewall4': remote('opkg status firewall4').splitlines()[:2],
                  'mutations': False}, indent=2))
