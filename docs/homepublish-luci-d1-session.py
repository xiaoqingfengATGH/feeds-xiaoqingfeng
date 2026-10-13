import pathlib, subprocess, json

repo = pathlib.Path(__file__).resolve().parents[1]
ssh = ['ssh', '-F', '/dev/null', '-i', 'D:/DevPortal/CloudHosts/HomePri.key', '-p', '222', '-o', 'BatchMode=yes', 'root@127.0.0.1']
sock = '/tmp/homepublish-luci-isolated/var/run/ubus/ubus.sock'
base = 'ubus -s /tmp/homepublish-luci-isolated/var/run/ubus/ubus.sock '

def call(obj, method, args):
    # The ubus CLI wants the message as ONE shell-quoted argv element, never stdin.
    remote = f"ubus -s {sock} call {obj} {method} '{json.dumps(args)}'"
    p = subprocess.run(ssh + [remote], capture_output=True, text=True)
    out = p.stdout.strip()
    if p.returncode != 0:
        raise SystemExit(f'{obj}.{method} failed: rc={p.returncode} {p.stderr.strip()} / stdout={out!r}')
    return json.loads(out) if out else None

# re-create session on the live chroot rpcd (urandom bind-mounted by fixture)
result = call('session', 'create', {'timeout': 3600})
print('session.create ->', result.get('ubus_rpc_session'))
sid = result['ubus_rpc_session']
acl = json.loads((repo / 'luci-app-homepublish/root/usr/share/rpcd/acl.d/luci-app-homepublish.json').read_text())['luci-app-homepublish']
objects = [['homepublish', 'status'], ['uci', 'get'], ['uci', 'changes'], ['uci', 'set'], ['uci', 'add'], ['uci', 'delete'], ['uci', 'order'], ['session', 'access']]
for method in acl.get('write', {}).get('ubus', {}).get('uci', []):
    objects.append(['uci', method])
for obj, fun in objects:
    call('session', 'grant', {'ubus_rpc_session': sid, 'scope': 'ubus', 'objects': [[obj, fun]]})
for cfg, perms in [('homepublish', ['read', 'write']), ('other', ['read', 'write']), ('luci', ['read'])]:
    for perm in perms:
        call('session', 'grant', {'ubus_rpc_session': sid, 'scope': 'uci', 'objects': [[cfg, perm]]})
call('session', 'set', {'ubus_rpc_session': sid, 'values': {'acls': {'luci-app-homepublish': ['read', 'write']}}})
call('uci', 'set', {'ubus_rpc_session': sid, 'config': 'other', 'section': 'main', 'values': {'value': 'staged-other'}})
(repo / 'docs/artifacts/luci-fixture-session.json').write_text(json.dumps({'sid': sid}))
print('Fixture session initialized using production homepublish ACL; unrelated config staged; sid stored')
