"""Real isolated router traffic acceptance; no production reload or firewall writes.
Run: python homepublish/tests/run-device-http-traffic.py
Private fixed source substitutions are recorded. Startup/socket ownership stays real.
"""
import hashlib
import io
import json
import os
from pathlib import Path
import shlex
import subprocess
import tarfile
import time
import uuid

REPO = Path(__file__).resolve().parents[2]
SOURCE = REPO / 'homepublish/files/usr/share/homepublish'
EVIDENCE = REPO / 'docs/evidence/input-firewall/http-traffic-private.json'
ROOT = '/root/homepublish-lua-store/http-traffic-' + uuid.uuid4().hex[:12]
NAME = 'homepublish-http-' + ROOT.rsplit('-', 1)[1]
RUNTIME = '/tmp/' + NAME
SSH = ['ssh', '-o', 'ProxyCommand=none', '-o', 'ProxyJump=none', '-o', 'IdentitiesOnly=yes', '-o', 'BatchMode=yes', '-i', os.environ.get('HOMEPUBLISH_SSH_KEY', 'D:/DevPortal/CloudHosts/HomePri.key'), 'root@' + os.environ.get('HOMEPUBLISH_SSH_HOST', '192.168.1.2')]
report = {'private_root': ROOT, 'service_name': NAME, 'boundary': 'Real nginx/sslh/provider/controller/private journal; firewall omitted ONLY in private fixed provider. Router-origin traffic; SSH banner fixture not authenticated SSH.', 'traffic': {}, 'commands': []}

def run(cmd, data=None, check=True):
    p = subprocess.run(SSH + [cmd], input=data, capture_output=True, timeout=90)
    r = {'command': cmd, 'code': p.returncode, 'stdout': p.stdout.decode(errors='replace'), 'stderr': p.stderr.decode(errors='replace')}
    report['commands'].append(r)
    if check and p.returncode:
        raise RuntimeError(str(r))
    return r['stdout']

def request(q):
    return json.loads(run('lua ' + ROOT + '/cli.lua', json.dumps(q).encode()))

def service(method, body):
    return run('ubus call service ' + method + ' ' + shlex.quote(json.dumps(body)))

def baseline():
    return run("sha256sum /etc/homepublish/product/state /etc/config/firewall /etc/config/homepublish /usr/share/homepublish/*.lua /usr/libexec/homepublish/*; ubus call service list '{\"name\":\"homepublish\"}'; nft -s list table inet fw4 | sha256sum")

def main():
    staged = False
    lifecycle = False
    error = None
    before = baseline()
    report['before'] = before
    try:
        # Hold sockets during allocation so all fixture ports are distinct.
        ports = json.loads(run("lua -e 'local n=require(\"nixio\");local a,s={},{};for i=1,7 do s[i]=assert(n.socket(\"inet\",\"stream\"));assert(s[i]:bind(\"127.0.0.1\",0));local _,p=s[i]:getsockname();a[i]=p end;print(require(\"luci.jsonc\").stringify(a))'"))
        shared, web1, web2, tls, ssh, raw, dedicated = ports
        report['ports'] = dict(zip(['shared', 'web1', 'web2', 'tls', 'ssh', 'raw', 'dedicated'], ports))
        blobs = {p.name: p.read_bytes() for p in SOURCE.glob('*.lua')}
        original = blobs['product-system-provider.lua'].decode()
        private = original.replace("name='homepublish-runtime',root='/tmp/homepublish-runtime'", "name='" + NAME + "',root='" + RUNTIME + "'")
        private = private.replace("firewall=require('product-firewall').new(),", "firewall=nil, -- private traffic acceptance: no nft mutation")
        assert private != original and "root='/tmp/homepublish-runtime'" not in private
        blobs['product-system-provider.lua'] = private.encode()
        blobs['product-store.lua'] = ("return dofile('" + ROOT + "/source/product-store-core.lua').new('" + ROOT + "/store')\n").encode()
        report['substitutions'] = {'product-system-provider.lua': ['fixed private procd name/runtime root', 'firewall=nil; no firewall acceptance claimed'], 'product-store.lua': 'fixed private journal root'}
        cli = "local source='" + ROOT + "'/source'\n"
        cli = "local source='" + ROOT + "/source';package.path=source..'/?.lua;'..package.path\nlocal J=require('product-json');local P=require('product-provider');local C=require('product-controller').new(require('product-system-provider'));assert(package.loaded.homepublish_store==nil);local q=J.decode(io.read('*a'));local r;if q.action=='start' then r=C.start(q.revision,q.approved) elseif q.action=='stop' then r=C.stop() else r=assert(P.handle(q,true)) end;print(J.encode(r))\n"
        buf = io.BytesIO()
        with tarfile.open(fileobj=buf, mode='w:gz') as tar:
            for name, data in list(('source/' + k, v) for k, v in blobs.items()) + [('cli.lua', cli.encode())]:
                info = tarfile.TarInfo(name); info.size = len(data); info.mode = 0o600
                tar.addfile(info, io.BytesIO(data))
        run('umask 077; mkdir ' + ROOT + ' && tar -xzf - -C ' + ROOT, buf.getvalue()); staged = True
        hashes = {k: hashlib.sha256(v).hexdigest() for k, v in blobs.items()}
        actual = {line.split()[1].rsplit('/', 1)[1]: line.split()[0] for line in run('sha256sum ' + ROOT + '/source/*.lua').splitlines()}
        assert hashes == actual
        report['source_sha256'] = hashes
        report['source_verified'] = True
        cert = json.loads(run("lua -e " + shlex.quote("package.path='" + ROOT + "/source/?.lua;'..package.path; print(require('product-json').encode(assert(require('device-integrations').certificate_source('acme:home.iwonderful.top','home.iwonderful.top'))))")))
        report['certificate'] = {'reference': 'acme:home.iwonderful.top', 'hostname': 'home.iwonderful.top', 'validation': 'curl system CA and hostname, no insecure flags'}
        backend = 'daemon off; master_process off; pid ' + ROOT + '/backend.pid; error_log ' + ROOT + '/backend.log; events {} http { access_log off; '
        for p, label in [(web1, 'HTTP_ONE'), (web2, 'HTTP_TWO')]:
            backend += 'server { listen 127.0.0.1:' + str(p) + '; location / { return 200 "' + label + '|$http_x_real_ip|$http_x_forwarded_for"; } } '
        backend += 'server { listen 127.0.0.1:' + str(tls) + ' ssl; ssl_certificate ' + cert['certificate'] + '; ssl_certificate_key ' + cert['key'] + '; location / { return 200 "TLS_PASSTHROUGH"; } } }'
        run('cat > ' + ROOT + '/backend.conf', backend.encode())
        run('mkdir ' + ROOT + '/logs')
        run("printf '#!/bin/sh\nprintf \"SSH-2.0-HOMEPUBLISH_PRIVATE\\\\r\\\\n\"\nsleep 1\n' > " + ROOT + '/banner.sh; chmod 700 ' + ROOT + '/banner.sh')
        instances = {
            'web': {'command': ['/usr/libexec/homepublish/nginx', '-p', ROOT + '/', '-c', 'backend.conf']},
            'ssh': {'command': ['/usr/bin/socat', 'TCP4-LISTEN:' + str(ssh) + ',bind=127.0.0.1,reuseaddr,fork', 'EXEC:' + ROOT + '/banner.sh']},
            'raw': {'command': ['/usr/bin/socat', 'TCP4-LISTEN:' + str(raw) + ',bind=127.0.0.1,reuseaddr,fork', 'EXEC:/bin/cat']}}
        service('set', {'name': NAME + '-backend', 'instances': instances}); time.sleep(1)
        report['backend_readback'] = json.loads(service('list', {'name': NAME + '-backend'}))
        services = []
        for ident, typ, port, host in [('one', 'http_proxy', web1, 'one.home.test'), ('two', 'http_proxy', web2, 'two.home.test'), ('secure', 'https_proxy', web1, 'home.iwonderful.top'), ('opaque', 'tls_passthrough', tls, 'opaque.home.test'), ('ssh', 'ssh', ssh, None), ('raw', 'tcp_forward', raw, None)]:
            s = {'service_id': ident, 'name': ident, 'enabled': True, 'type': typ, 'backend': {'addressFamily': 'ipv4', 'host': '127.0.0.1', 'port': port, 'allowed_ranges': ['127.0.0.0/8']}, 'authentication_review': {'authentication': 'confirmed', 'management': False}}
            if host: s['hostname'] = host
            if typ in ('https_proxy', 'http_proxy'): s['upstream_scheme'] = 'http'
            if typ == 'https_proxy': s['certificate_mode'] = 'inherit'
            if typ == 'tcp_forward': s['listen_port'] = dedicated
            services.append(s)
        config = {'schema_version': 2, 'default_certificate_ref': 'acme:home.iwonderful.top', 'access_profile': {'listeners': [{'listener_id': 'private', 'family': 'ipv4', 'network': 'lan', 'address': '192.168.1.2', 'port': shared}]}, 'publication_policy': {'mode': 'continuous', 'boot_restore': False}, 'services': services}
        state = request({'action': 'status'}); lifecycle = True
        saved = request({'action': 'save', 'expected_revision': state['saved_revision'], 'config': config}); report['saved'] = saved
        assert 'saved_revision' in saved, saved
        started = request({'action': 'start', 'revision': saved['saved_revision'], 'approved': True}); report['started'] = started
        assert started.get('runtime', {}).get('phase') == 'running', started
        assert all(x['ready'] for x in started['runtime']['services'].values())
        report['runtime_readback'] = json.loads(service('list', {'name': NAME}))
        report['rendered_configuration'] = run('cat ' + RUNTIME + '/nginx.conf ' + RUNTIME + '/sslh.cfg')
        report['listener_manifest'] = json.loads(run('cat ' + RUNTIME + '/listeners.json'))
        report['engine_sha256'] = run('sha256sum /usr/libexec/homepublish/nginx /usr/libexec/homepublish/sslh-select')
        base = "env -u CURL_CA_BUNDLE -u SSL_CERT_FILE -u SSL_CERT_DIR curl -q --noproxy '*' --silent --show-error --max-time 8 "
        for host, label in [('one.home.test', 'HTTP_ONE'), ('two.home.test', 'HTTP_TWO')]:
            out = run(base + '--fail --resolve ' + shlex.quote(host + ':' + str(shared) + ':192.168.1.2') + ' http://' + host + ':' + str(shared) + '/')
            assert out == label + '|192.168.1.2|192.168.1.2', repr(out)
            report['traffic'][host] = out
        out = run(base + "-o /dev/null -w '%{http_code}' --resolve " + shlex.quote('unknown.home.test:' + str(shared) + ':192.168.1.2') + ' http://unknown.home.test:' + str(shared) + '/', check=False)
        assert out in ('000', '400', '404', '421', '444'), out
        report['traffic']['unknown_host_rejected'] = out
        out = run(base + '--fail --resolve ' + shlex.quote('home.iwonderful.top:' + str(shared) + ':192.168.1.2') + ' https://home.iwonderful.top:' + str(shared) + '/')
        assert out.startswith('HTTP_ONE|'), out
        report['traffic']['https_verified'] = out
        out = run("printf 'GET / HTTP/1.0\\r\\nHost: opaque.home.test\\r\\n\\r\\n' | timeout 12 openssl s_client -quiet -verify_return_error -verify_hostname home.iwonderful.top -connect 192.168.1.2:" + str(shared) + ' -servername opaque.home.test')
        assert 'TLS_PASSTHROUGH' in out, out
        report['traffic']['tls_passthrough_verified'] = out
        lua = "local n=require('nixio');local s=assert(n.socket('inet','stream'));s:setopt('socket','rcvtimeo',8);assert(s:connect('192.168.1.2',PORT));BODY;s:close()"
        out = run('lua -e ' + shlex.quote(lua.replace('PORT', str(shared)).replace('BODY', "assert(s:send('SSH-2.0-PRIVATE_CLIENT\\r\\n'));print(assert(s:recv(128)))")))
        assert 'SSH-2.0-HOMEPUBLISH_PRIVATE' in out, out
        report['traffic']['ssh_banner'] = out
        out = run('lua -e ' + shlex.quote(lua.replace('PORT', str(dedicated)).replace('BODY', "assert(s:send('PRIVATE_TCP')==11);assert(s:recv(11)=='PRIVATE_TCP');print('PRIVATE_TCP')")))
        report['traffic']['dedicated_tcp_echo'] = out
    except Exception as exc:
        error = repr(exc)
        report['error'] = error
    finally:
        if lifecycle:
            try:
                report['stopped'] = request({'action': 'stop'})
                assert report['stopped']['runtime']['cleanup'] == 'confirmed'
            except Exception as exc:
                report['cleanup_error'] = repr(exc)
        if staged:
            service('delete', {'name': NAME + '-backend'})
            time.sleep(2)
            report['cleanup_readback'] = {'runtime': json.loads(service('list', {'name': NAME})), 'backend': json.loads(service('list', {'name': NAME + '-backend'}))}
            report['private_processes'] = run("ps w | grep -E " + shlex.quote(ROOT + '|' + RUNTIME) + " | grep -v grep || true")
            rows = run('cat /proc/net/tcp /proc/net/tcp6')
            owned_ports = set(report.get('ports', {}).values()) | {x['port'] for x in report.get('listener_manifest', [])}
            report['private_listeners_remaining'] = [line for line in rows.splitlines() if len(line.split()) > 3 and line.split()[3] == '0A' and int(line.split()[1].split(':')[1], 16) in owned_ports]
            assert not report['private_listeners_remaining'], report['private_listeners_remaining']
            assert report['cleanup_readback'] == {'runtime': {}, 'backend': {}}
            report['private_runtime_absent'] = run('test ! -e ' + RUNTIME + '; echo $?').strip() == '0'
            # Delete only our UUID private root after owned runtime has confirmed stop.
            if report.get('stopped', {}).get('runtime', {}).get('cleanup') == 'confirmed' and not report['private_processes']:
                run('rm -rf ' + ROOT + '; test ! -e ' + ROOT)
                report['private_root_removed'] = True
        after = baseline(); report['after'] = after; report['production_unchanged'] = before == after
        report['passed'] = not error and not report.get('cleanup_error') and report['production_unchanged'] and report.get('private_root_removed', False) and len(report['traffic']) == 7
        EVIDENCE.parent.mkdir(parents=True, exist_ok=True)
        EVIDENCE.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps({k: report.get(k) for k in ('passed', 'traffic', 'error', 'cleanup_error', 'production_unchanged', 'cleanup_readback', 'private_root_removed')}, indent=2))
    return 0 if report['passed'] else 1

if __name__ == '__main__':
    raise SystemExit(main())
