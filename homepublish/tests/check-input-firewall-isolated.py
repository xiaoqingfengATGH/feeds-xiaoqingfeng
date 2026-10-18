#!/usr/bin/env python
"""Opt-in isolated live acceptance; no production deployment or service operations.
Uses real adapter/worker with ONLY fixed private transport/bootstrap paths changed.
Requires an otherwise empty HomePublish INPUT ownership namespace. LAN TCP success
is not evidence of default-deny behavior. Evidence retains full nft JSON snapshots.
"""
import argparse, hashlib, io, json, pathlib, shlex, socket, subprocess, tarfile, time, uuid

REPO = pathlib.Path(__file__).resolve().parents[2]
SOURCE = REPO / 'homepublish/files/usr/share/homepublish'
SSH = ['ssh', '-i', 'D:/DevPortal/CloudHosts/HomePri.key', '-o', 'BatchMode=yes', '-o', 'IdentitiesOnly=yes', '-o', 'ProxyCommand=none', '-o', 'ProxyJump=none', 'root@192.168.1.2']
OWNER = 'homepublish:input:v1'

def remote(command, data=None):
    p = subprocess.run(SSH + [command], input=data, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30)
    if p.returncode:
        raise RuntimeError(f'{command}: {p.returncode}: {p.stderr.decode(errors="replace")}')
    return p.stdout.decode()

def owned(s):
    return [e for e in s['nftables'] if any(isinstance(v, dict) and (v.get('comment') == OWNER or v.get('name', '').startswith('homepublish_in')) for v in e.values())]

def normalize(s):
    def walk(x):
        if isinstance(x, dict):
            return {k: ({} if k == 'counter' else walk(v)) for k, v in x.items()}
        if isinstance(x, list): return [walk(v) for v in x]
        return x
    return walk(s)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--execute', action='store_true', required=True)
    parser.add_argument('--evidence', required=True)
    args = parser.parse_args()
    out = pathlib.Path(args.evidence); out.mkdir(parents=True, exist_ok=False)
    root = '/root/homepublish-lua-store/input-acceptance/' + uuid.uuid4().hex
    evidence = {'private_root': root, 'events': [], 'limitations': ['Private fixed transport paths and private bootstrap marker; production fw4 include is absent and not installed.', 'LAN already ACCEPTs: TCP success does not prove denied ingress opens or blocks after expiry.', 'No production firewall reload or controller termination tested.']}
    def save(): (out / 'result.json').write_text(json.dumps(evidence, indent=2), encoding='utf-8')
    def snapshot(name):
        s = json.loads(remote('nft -j list table inet fw4'))
        (out / (name + '.nft.json')).write_text(json.dumps(s, indent=2), encoding='utf-8')
        return s
    def integrity():
        return remote("sha256sum /etc/config/firewall /etc/config/homepublish /usr/share/homepublish/*; for p in 58278 58575 58576; do cat /proc/$p/stat; done")
    before = snapshot('before')
    assert not owned(before), 'Existing owned feature namespace; unsafe to reconcile'
    evidence['integrity_before'] = integrity()
    remote("test -x /sbin/fw4; cat /usr/share/nftables.d/README; nft --version; command -v flock; command -v timeout")
    ports = remote('cat /proc/net/tcp /proc/net/tcp6')
    port = next(p for p in range(62171, 62250) if f':{p:04X} ' not in ports and str(p) not in json.dumps(before))
    evidence['port'] = port
    files = {}
    for name in ['product-firewall.lua', 'product-firewall-system.lua', 'product-firewall-apply.lua', 'product-json.lua', 'direct-address.lua']:
        text = (SOURCE / name).read_text(encoding='utf-8')
        evidence.setdefault('source_sha256', {})[name] = hashlib.sha256((SOURCE / name).read_bytes()).hexdigest()
        if name == 'product-firewall-system.lua':
            text = text.replace("'/var/run/homepublish-firewall'", repr(root + '/requests')).replace('/usr/share/homepublish/product-firewall-apply.lua', root + '/product-firewall-apply.lua')
        if name == 'product-firewall-apply.lua':
            text = text.replace('/usr/share/homepublish/?.lua', root + '/?.lua').replace('^/var/run/homepublish%-firewall/%d+%-%d+$', '^' + root.replace('-', '%-') + '/requests/%d+%-%d+$').replace('/usr/share/nftables.d/table-post/90-homepublish.nft', root + '/bootstrap.nft')
        files[name] = text.encode()
    files['permission-contract.lua'] = ("local fs=require('nixio.fs');local p=" + repr(root + '/permission-probe') + ";local ok=pcall(fs.mkdir,p,448);assert(not ok,'decimal 448 unexpectedly accepted');assert(fs.mkdir(p,'700'));assert(fs.chmod(p,'700'));assert(fs.lstat(p).modedec==700);assert(fs.rmdir(p));print('nixio octal 700 accepted; decimal 448 rejected; mode readback 700; probe removed')").encode()
    files['bootstrap.nft'] = b'# Private acceptance marker, not installed in fw4 includes\n'
    controller = """package.path='ROOT/?.lua;'..package.path
local F=require('product-firewall').new()
local J=require('product-json');local n=require('nixio')
local rules={{family='ipv4',zone='lan',protocol='tcp',port=PORT,dest_ip='192.168.1.2'},{family='ipv6',zone='lan',protocol='tcp',port=PORT,dest_ip='fd89:878e:a47f::1'}}
local function event(name,ok,err) io.write(J.encode({event=name,ok=ok,error=err,status=F.status(),pid=n.getpid(),uptime=n.sysinfo().uptime})..'\\n');io.flush() end
local function run(name,r) local ok,err=F.reconcile(r,10);event(name,ok,err);assert(ok,err) end
if arg[1]=='clear' then run('emergency_clear',{});return end
run('installed',rules);n.nanosleep(3)
event('before_refresh',true);n.nanosleep(2)
run('refreshed',rules);n.nanosleep(3)
run('stopped_cleanup',{});n.nanosleep(3)
run('expiry_installed',rules);n.nanosleep(12)
event('expired_no_refresh',true);n.nanosleep(3)
run('final_cleanup',{});n.nanosleep(3)
""".replace('ROOT', root).replace('PORT', str(port))
    files['controller.lua'] = controller.encode()
    archive = io.BytesIO()
    with tarfile.open(fileobj=archive, mode='w') as tar:
        for name, data in files.items():
            info = tarfile.TarInfo(name); info.size = len(data); info.mode = 0o600; tar.addfile(info, io.BytesIO(data))
    remote('mkdir -p ' + root + '; chmod 700 ' + root + '; tar -xf - -C ' + root, archive.getvalue())
    for name, data in files.items(): (out / name).write_bytes(data)
    listener = None
    process = None
    active = False
    try:
        evidence['nixio_permission_contract'] = remote('lua ' + root + '/permission-contract.lua')
        code = "import socket,sys,select; s=socket.socket(); s.bind(('192.168.1.2',%d)); s.listen(8); print('READY',flush=True);\nwhile True:\n r,_,_=select.select([s,sys.stdin],[],[],60)\n if not r or sys.stdin in r: break\n c,a=s.accept(); c.sendall(b'homepublish-isolated-acceptance\\n'); c.close()" % port
        listener = subprocess.Popen(SSH + ['python3 -u -c ' + shlex.quote(code)], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        assert listener.stdout.readline().strip() == b'READY', 'Private listener unavailable'
        active = True
        process = subprocess.Popen(SSH + ['lua ' + root + '/controller.lua'], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        for line in process.stdout:
            event = json.loads(line); evidence['events'].append(event)
            s = snapshot(event['event']); event['owned'] = owned(s)
            if event['event'] in ['installed', 'before_refresh', 'refreshed', 'expiry_installed']:
                assert event['ok'] and len([e for e in owned(s) if 'rule' in e]) == 2, event
                sets = [e['set'] for e in owned(s) if 'set' in e and e['set']['name'] != 'homepublish_input_guard']
                assert len(sets) == 2
                event['remaining_seconds'] = {}
                for item in sets:
                    assert item['type'] == 'inet_service' and item['flags'] == ['timeout'] and 0 < item['timeout'] <= 10
                    assert len(item['elem']) == 1
                    element = item['elem'][0]['elem']
                    assert element['val'] == port and 0 < element['expires'] <= element.get('timeout', item['timeout']) <= 10
                    event['remaining_seconds'][item['name']] = element['expires']
                if event['event'] == 'refreshed':
                    previous = next(e for e in evidence['events'] if e['event'] == 'before_refresh')
                    assert all(v > previous['remaining_seconds'][k] for k, v in event['remaining_seconds'].items()), 'Refresh did not extend kernel expiry'
                    evidence['refresh_extended_kernel_expiry'] = True
                with socket.create_connection(('192.168.1.2', port), timeout=3) as c:
                    event['windows_tcp_response'] = c.recv(100).decode()
            if event['event'] in ['stopped_cleanup', 'final_cleanup']:
                assert not [e for e in owned(s) if 'rule' in e or ('set' in e and e['set']['name'] != 'homepublish_input_guard')]
            if event['event'] == 'expired_no_refresh':
                sets = [e['set'] for e in owned(s) if 'set' in e and e['set']['name'] != 'homepublish_input_guard']
                assert len(sets) == 2 and all(not s.get('elem') for s in sets), 'Kernel elements did not expire'
            save()
        assert process.wait(timeout=10) == 0, process.stderr.read().decode()
        assert len(evidence['events']) == 7
        evidence['acceptance_passed'] = True
    except Exception as exc:
        evidence['error'] = str(exc)
    finally:
        # Even on assertion failure, let only the private controller finish
        # naturally before cleanup, so it cannot recreate rules after readback.
        if process:
            evidence['private_controller_returncode'] = process.wait(timeout=45)
            evidence['private_controller_stderr'] = process.stderr.read().decode()
        if listener:
            listener.stdin.close(); listener.wait(timeout=10)
            evidence['listener_returncode'] = listener.returncode
        if active:
            try:
                evidence['fallback_clear'] = remote('lua ' + root + '/controller.lua clear')
            except Exception as exc:
                evidence['fallback_clear_error'] = str(exc)
        # Remove only the guard this run created, after exact scoped readback.
        cleanup = snapshot('pre_guard_cleanup')
        remaining = owned(cleanup)
        assert all('set' in e and e['set']['name'] == 'homepublish_input_guard' and e['set'].get('type') == 'inet_service' and not e['set'].get('elem') for e in remaining), 'Unexpected owned objects; refuse broad cleanup'
        if remaining:
            remote("flock -x /var/run/fw4.lock nft delete set inet fw4 homepublish_input_guard")
        final = snapshot('after')
        evidence['owned_final'] = owned(final)
        evidence['unowned_rules_unchanged'] = normalize(before) == normalize(final)
        evidence['integrity_after'] = integrity()
        # proc stat CPU/time fields change; compare process identity field 22 only.
        b = evidence['integrity_before'].splitlines(); a = evidence['integrity_after'].splitlines()
        evidence['production_files_unchanged'] = [x for x in b if '  /' in x] == [x for x in a if '  /' in x]
        evidence['production_pid_start_unchanged'] = [(x.split()[0], x.split()[21]) for x in b if ' (' in x] == [(x.split()[0], x.split()[21]) for x in a if ' (' in x]
        tcp_final = remote('cat /proc/net/tcp /proc/net/tcp6')
        (out / 'after.proc-net-tcp.txt').write_text(tcp_final, encoding='utf-8')
        evidence['listener_absent_final'] = not any(len(fields) > 3 and fields[1].endswith(f':{port:04X}') and fields[3] == '0A' for fields in map(str.split, tcp_final.splitlines()))
        save()
    print(json.dumps({k:v for k,v in evidence.items() if k not in ['events','integrity_before','integrity_after']}, indent=2))
    assert evidence.get('acceptance_passed') and not evidence['owned_final'] and evidence['unowned_rules_unchanged'] and evidence['production_files_unchanged'] and evidence['production_pid_start_unchanged'] and evidence['listener_absent_final']

if __name__ == '__main__': main()
