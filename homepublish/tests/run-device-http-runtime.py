"""Run the same HTTP runtime contracts on private real-device Lua sources.
No production files, configuration, firewall rules or controller are changed.
"""
import ast
import hashlib
import io
import json
import os
import pathlib
import subprocess
import tarfile
import uuid

REPO = pathlib.Path(__file__).resolve().parents[2]
SOURCE = REPO / 'homepublish/files/usr/share/homepublish'
REMOTE = '/root/homepublish-lua-store/http-runtime-' + uuid.uuid4().hex[:12]
SSH = ['ssh', '-o', 'ProxyCommand=none', '-o', 'ProxyJump=none', '-o', 'IdentitiesOnly=yes', '-o', 'BatchMode=yes', '-i', os.environ.get('HOMEPUBLISH_SSH_KEY', 'D:/DevPortal/CloudHosts/HomePri.key'), 'root@' + os.environ.get('HOMEPUBLISH_SSH_HOST', '192.168.1.2')]

def run(command, data=None):
    p = subprocess.run(SSH + [command], input=data, capture_output=True, timeout=120)
    return {'command': command, 'code': p.returncode, 'stdout': p.stdout.decode(errors='replace'), 'stderr': p.stderr.decode(errors='replace')}

def main():
    tree = ast.parse((REPO / 'homepublish/tests/test-http-runtime.py').read_text())
    cls = next(n for n in tree.body if isinstance(n, ast.ClassDef))
    methods = {n.name: n for n in cls.body if isinstance(n, ast.FunctionDef)}
    def chunks(method):
        return [n.args[0].value for n in ast.walk(method) if isinstance(n, ast.Call) and isinstance(n.func, ast.Attribute) and n.func.attr == 'execute' and n.args and isinstance(n.args[0], ast.Constant)]
    setup = chunks(methods['lua'])[-1]
    cases = {name: '\n'.join(chunks(method)) for name, method in methods.items() if name.startswith('test_') and name != 'test_provider_allocates_distinct_collision_safe_http_port'}
    cases['test_provider_allocates_distinct_collision_safe_http_port'] = (REPO/'homepublish/tests/device-http-provider.lua').read_text()
    buf = io.BytesIO()
    hashes = {}
    with tarfile.open(fileobj=buf, mode='w:gz') as tar:
        for p in SOURCE.glob('*.lua'):
            tar.add(p, arcname='source/'+p.name)
            hashes[p.name] = hashlib.sha256(p.read_bytes()).hexdigest()
        for name, body in cases.items():
            data = ("local source='" + REMOTE + "/source';package.path=source..'/?.lua;'..package.path;arg={source}\n" + setup + '\n' + body + "\nprint('"+name+" GREEN')\n").encode()
            info = tarfile.TarInfo(name+'.lua');info.size = len(data);info.mode = 0o600
            tar.addfile(info, io.BytesIO(data))
    baseline = 'sha256sum /etc/homepublish/product/state /etc/config/firewall'
    before = run(baseline)
    staged = run('umask 077; mkdir '+REMOTE+' && tar -xzf - -C '+REMOTE, buf.getvalue())
    verified = run('sha256sum '+REMOTE+'/source/*.lua') if staged['code']==0 else {'code': 1, 'stdout': ''}
    remote_hashes = {path.rsplit('/',1)[-1]: digest for digest, path in (line.split(None,1) for line in verified['stdout'].splitlines())}
    source_verified = verified['code']==0 and remote_hashes == hashes
    results = {}
    if staged['code'] == 0 and source_verified:
        for name in cases:
            results[name] = run('lua '+REMOTE+'/'+name+'.lua')
    after = run(baseline)
    result = {'private_root': REMOTE, 'source_sha256': hashes, 'source_verified': source_verified, 'before': before, 'staged': staged, 'cases': results, 'after': after, 'unchanged': before['code']==0 and before['stdout']==after['stdout']}
    evidence = REPO/'docs/evidence/input-firewall/http-runtime-private.json'
    evidence.parent.mkdir(parents=True, exist_ok=True)
    evidence.write_text(json.dumps(result, indent=2)+'\n')
    print(json.dumps({k:v for k,v in result.items() if k != 'source_sha256'}, indent=2))
    return 0 if result['unchanged'] and len(results)==len(cases) and all(r['code']==0 for r in results.values()) else 1

if __name__ == '__main__':
    raise SystemExit(main())
