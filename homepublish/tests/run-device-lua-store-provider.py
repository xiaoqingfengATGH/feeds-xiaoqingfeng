#!/usr/bin/env python3
"""Stage current Lua sources and exercise provider in a private target store."""
import argparse
import hashlib
import json
import pathlib
import subprocess
import uuid

p = argparse.ArgumentParser()
p.add_argument('--host', required=True)
p.add_argument('--port', default='22')
p.add_argument('--key', required=True)
p.add_argument('--evidence', type=pathlib.Path, required=True)
a = p.parse_args()
repo = pathlib.Path(__file__).resolve().parents[2]
ssh = ['ssh', '-o', 'ProxyCommand=none', '-o', 'ProxyJump=none', '-o',
       'StrictHostKeyChecking=yes', '-o', 'IdentitiesOnly=yes', '-o',
       'BatchMode=yes', '-i', a.key, '-p', a.port, 'root@' + a.host]
root = '/root/homepublish-lua-store/provider-' + uuid.uuid4().hex
source = root + '/source'
def remote(command, data=None):
    return subprocess.run(ssh + [command], input=data, capture_output=True, timeout=60)
def checked(command, data=None):
    r = remote(command, data)
    if r.returncode:
        raise RuntimeError(r.stderr.decode(errors='replace'))
    return r.stdout.decode(errors='replace')
before = checked('sha256sum /etc/homepublish/product/state').split()[0]
checked('umask 077; mkdir -p ' + source)
manifest = {}
files = list((repo / 'homepublish/files/usr/share/homepublish').glob('*.lua'))
files.append(repo / 'homepublish/tests/device-lua-store-provider.lua')
for path in files:
    data = path.read_bytes()
    expected = hashlib.sha256(data).hexdigest()
    target = source + '/' + path.name
    checked('cat > ' + target, data)
    assert checked('sha256sum ' + target).split()[0] == expected
    manifest[path.name] = expected
command = 'lua ' + source + '/device-lua-store-provider.lua ' + source + ' ' + root
r = remote(command)
after = checked('sha256sum /etc/homepublish/product/state').split()[0]
log = r.stdout.decode(errors='replace') + r.stderr.decode(errors='replace')
log += '\nEXIT_CODE=' + str(r.returncode) + '\n'
a.evidence.mkdir(parents=True, exist_ok=True)
label = 'provider-' + uuid.uuid4().hex
(a.evidence / (label + '.log')).write_text(log, encoding='utf-8')
(a.evidence / (label + '.json')).write_text(json.dumps(dict(
    host=a.host, port=a.port, command=command, root=root, source_sha256=manifest,
    live_before=before, live_after=after, returncode=r.returncode), indent=2), encoding='utf-8')
print(log, end='')
assert before == after, 'live journal changed during isolated integration'
raise SystemExit(r.returncode)
