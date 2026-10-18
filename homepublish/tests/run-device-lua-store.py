#!/usr/bin/env python
"""Upload/run real OpenWrt Lua tests; never access the production store."""
import argparse
import hashlib
import json
from pathlib import Path
import shlex
import subprocess
import sys
import datetime
import uuid

p = argparse.ArgumentParser()
p.add_argument('--host', required=True)
p.add_argument('--port', type=int, default=22)
p.add_argument('--key', required=True)
p.add_argument('--case', default='contract')
p.add_argument('--label', default='run')
p.add_argument('--evidence', required=True)
a = p.parse_args()
repo = Path(__file__).resolve().parents[2]
root = '/root/homepublish-lua-store'
ssh = ['ssh', '-o', 'ProxyCommand=none', '-o', 'ProxyJump=none', '-o', 'BatchMode=yes', '-o', 'IdentitiesOnly=yes', '-o', 'StrictHostKeyChecking=yes', '-i', a.key, '-p', str(a.port), 'root@' + a.host]
def remote(command, data=None):
    return subprocess.run(ssh + [command], input=data, capture_output=True)
assert a.case.replace('-', '').isalnum()
out = Path(a.evidence)
out.mkdir(parents=True, exist_ok=True)
record = {'case': a.case, 'label': a.label, 'timestamp': datetime.datetime.now(datetime.timezone.utc).isoformat(), 'files': {}}
r = remote('mkdir -p ' + root + '/source && chmod 700 ' + root + ' ' + root + '/source')
if r.returncode:
    sys.exit(r.returncode)
for rel in ['homepublish/tests/device-lua-store.lua'] + [str(f.relative_to(repo)).replace('\\', '/') for f in sorted((repo / 'homepublish/files/usr/share/homepublish').glob('*.lua'))]:
    src = repo / rel
    if not src.exists():
        continue
    data = src.read_bytes().replace(b'\r\n', b'\n')
    target = root + '/source/' + src.name
    r = remote('cat > ' + shlex.quote(target) + ' && chmod 600 ' + shlex.quote(target), data)
    if r.returncode:
        sys.exit(r.returncode)
    digest = hashlib.sha256(data).hexdigest()
    check = remote('sha256sum ' + shlex.quote(target))
    assert check.returncode == 0 and check.stdout.decode().split()[0] == digest
    record['files'][rel] = digest
command = 'lua ' + root + '/source/device-lua-store.lua ' + a.case + '-' + uuid.uuid4().hex[:12]
r = remote(command)
text = r.stdout.decode(errors='replace') + r.stderr.decode(errors='replace')
record.update(command=command, exit_code=r.returncode)
(out / (a.label + '.log')).write_text(text, encoding='utf-8')
(out / (a.label + '.json')).write_text(json.dumps(record, indent=2), encoding='utf-8')
print(text, end='')
print('EXIT_CODE=' + str(r.returncode))
sys.exit(r.returncode)
