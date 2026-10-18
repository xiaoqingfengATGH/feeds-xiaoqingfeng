"""Target-only Host contract, private CLI persistence and actual nginx vhost traffic.
No production installation/config saves, firewall changes or DNS lookups.
"""
import argparse
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import shlex
import tarfile
import time

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('traffic_support', HERE / 'run-device-upstream-tls-traffic.py')
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
m.EVIDENCE = m.REPO / 'docs/evidence/lua-store/backend-host-header-traffic.json'

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--schema-only', action='store_true')
    ap.add_argument('--legacy-renderer', action='store_true', help='Negative control: private renderer omits the override')
    args = ap.parse_args()
    r = m.report
    r['boundary'] = 'Real target Lua/nixio; fixed private source/store/provider; real installed nginx/sslh. No production writes. HTTPS backend is a private self-signed fixture with verification explicitly off; public HTTPS uses normal CA/hostname verification.'
    before = m.baseline()
    staged = lifecycle = False
    error = None
    try:
        blobs = {p.name: p.read_bytes() for p in m.SOURCE.glob('*.lua')}

        original = blobs['product-system-provider.lua'].decode()
        private = original.replace("name='homepublish-runtime',root='/tmp/homepublish-runtime'", "name='" + m.NAME + "',root='" + m.RUNTIME + "'")
        private = private.replace("firewall=require('product-firewall').new(),", 'firewall=nil, -- private Host test; no firewall mutation')
        assert private != original and "root='/tmp/homepublish-runtime'" not in private
        blobs['product-system-provider.lua'] = private.encode()
        blobs['product-store.lua'] = ("return dofile('" + m.ROOT + "/source/product-store-core.lua').new('" + m.ROOT + "/store')\n").encode()
        cli = "local source='" + m.ROOT + "/source';package.path=source..'/?.lua;'..package.path;local J=require('product-json');local P=require('product-provider');local C=require('product-controller').new(require('product-system-provider'));assert(package.loaded.homepublish_store==nil);local q=J.decode(io.read('*a'));local r;if q.action=='start' then r=C.start(q.revision,q.approved) elseif q.action=='stop' then r=C.stop() else r=assert(P.handle(q,true)) end;print(J.encode(r))"
        contract = "SOURCE='" + m.ROOT + "/source';package.path=SOURCE..'/?.lua;'..package.path\n" + (HERE / 'device-backend-host-header.lua').read_text()
        buf = io.BytesIO()
        with tarfile.open(fileobj=buf, mode='w:gz') as tar:
            for name, data in [('source/' + k, v) for k, v in blobs.items()] + [('cli.lua', cli.encode()), ('contract.lua', contract.encode())]:
                info = tarfile.TarInfo(name); info.size = len(data); info.mode = 0o600; tar.addfile(info, io.BytesIO(data))
        m.run('umask 077; mkdir ' + m.ROOT + ' && tar -xzf - -C ' + m.ROOT, buf.getvalue()); staged = True
        r['source_sha256'] = m.run('sha256sum ' + m.ROOT + '/source/*.lua')
        actual = {line.split()[1].rsplit('/', 1)[1]: line.split()[0] for line in r['source_sha256'].splitlines()}
        assert actual == {name: hashlib.sha256(data).hexdigest() for name, data in blobs.items()}
        r['source_verified'] = True
        r['schema'] = m.run('lua ' + m.ROOT + '/contract.lua')
        if args.legacy_renderer:
            renderer = blobs['direct-renderer.lua'].decode()
            assert '(host_header or s.hostname)' in renderer
            m.run('cat > ' + m.ROOT + '/source/direct-renderer.lua', renderer.replace('(host_header or s.hostname)', 's.hostname').encode())
            r['negative_control_renderer_sha256'] = m.run('sha256sum ' + m.ROOT + '/source/direct-renderer.lua')
        if not args.schema_only:
            ports = json.loads(m.run("lua -e 'local n=require(\"nixio\");local a,s={},{};for i=1,3 do s[i]=assert(n.socket(\"inet\",\"stream\"));assert(s[i]:bind(\"127.0.0.1\",0));local _,p=s[i]:getsockname();a[i]=p end;print(require(\"luci.jsonc\").stringify(a))'"))
            shared, http, https = ports
            r['ports'] = dict(zip(['shared', 'http', 'https'], ports))
            m.run('openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj /CN=upstream-sni.home.test -keyout ' + m.ROOT + '/fixture.key -out ' + m.ROOT + '/fixture.pem')
            # Separate default and named vhosts: a successful response proves Host routing,
            # not merely echoing a header. $ssl_server_name independently proves backend SNI.
            backend = 'daemon off; master_process off; pid ' + m.ROOT + '/backend.pid; error_log ' + m.ROOT + '/backend.log; events {} http { access_log off; '
            for p, tls in [(http, False), (https, True)]:
                listen = 'listen 127.0.0.1:' + str(p) + (' ssl' if tls else '') + ';'
                cert = ('ssl_certificate ' + m.ROOT + '/fixture.pem; ssl_certificate_key ' + m.ROOT + '/fixture.key;') if tls else ''
                for name, label in [('_', 'WRONG_VHOST'), ('backend.home.test', 'HOST_VHOST'), ('one.home.test home.iwonderful.top', 'LEGACY_VHOST')]:
                    backend += 'server { ' + listen + cert + ' server_name ' + name + '; location / { return 200 "' + label + '|$http_host|$ssl_server_name"; } } '
            backend += '}'
            m.run('cat > ' + m.ROOT + '/backend.conf', backend.encode())
            m.run('mkdir ' + m.ROOT + '/logs; /usr/libexec/homepublish/nginx -t -p ' + m.ROOT + '/ -c backend.conf')
            m.service('set', {'name': m.NAME + '-backend', 'instances': {'web': {'command': ['/usr/libexec/homepublish/nginx', '-p', m.ROOT + '/', '-c', 'backend.conf']}}})
            time.sleep(1)
            r['backend_readback'] = json.loads(m.service('list', {'name': m.NAME + '-backend'}))
            services = []
            for ident, typ, host in [('one', 'http_proxy', 'one.home.test'), ('secure', 'https_proxy', 'home.iwonderful.top')]:
                s = {'service_id': ident, 'name': ident, 'enabled': True, 'type': typ, 'hostname': host, 'upstream_scheme': 'http', 'backend': {'addressFamily': 'ipv4', 'host': '127.0.0.1', 'port': http}}
                if typ == 'https_proxy': s['certificate_mode'] = 'inherit'
                services.append(s)
            config = {'schema_version': 2, 'default_certificate_ref': 'acme:home.iwonderful.top', 'access_profile': {'listeners': [{'listener_id': 'private', 'family': 'ipv4', 'network': 'lan', 'address': '192.168.1.2', 'port': shared}]}, 'services': services}
            state = m.request({'action': 'status'}); lifecycle = True
            for mode, scheme, header in [('legacy_http', 'http', None), ('custom_http', 'http', 'backend.home.test:8443'), ('custom_https', 'https', 'backend.home.test'), ('empty_https', 'https', '')]:
                if mode != 'legacy_http':
                    stopped = m.request({'action': 'stop'}); assert stopped['runtime']['cleanup'] == 'confirmed', stopped
                for s in services:
                    s['upstream_scheme'] = scheme
                    s['backend']['port'] = https if scheme == 'https' else http
                    if header is not None: s['backend']['host_header'] = header
                    if scheme == 'https': s['upstream_tls'] = {'verify': False, 'server_name': 'upstream-sni.home.test'}
                state = m.request({'action': 'status'})
                saved = m.request({'action': 'save', 'expected_revision': state['saved_revision'], 'config': config})
                assert 'saved_revision' in saved, saved
                readback = m.request({'action': 'status'})
                r.setdefault('persistence', {})[mode] = readback
                # Status is a new CLI process reading the actual private journal.
                assert readback['saved_revision'] == saved['saved_revision'], readback
                for s in readback['saved_config']['services']:
                    assert s['backend'].get('host_header') == (header or None), s
                    assert bool(header) == ('host_header' in s['backend']), s
                started = m.request({'action': 'start', 'revision': saved['saved_revision'], 'approved': True})
                assert started.get('runtime', {}).get('phase') == 'running', started
                active = m.request({'action': 'status'})
                assert active['active_revision'] == saved['saved_revision'], active
                for s in active['active_config']['services']:
                    assert s['backend'].get('host_header') == (header or None), s
                    assert bool(header) == ('host_header' in s['backend']), s
                r.setdefault('active_readbacks', {})[mode] = active
                rendered = m.run('cat ' + m.RUNTIME + '/nginx.conf')
                r.setdefault('listener_manifests', {})[mode] = json.loads(m.run('cat ' + m.RUNTIME + '/listeners.json'))
                r.setdefault('rendered', {})[mode] = rendered
                assert 'proxy_set_header X-Forwarded-Host' not in rendered
                for entry, host in [('http', 'one.home.test'), ('https', 'home.iwonderful.top')]:
                    curl = "env -u CURL_CA_BUNDLE -u SSL_CERT_FILE -u SSL_CERT_DIR curl -q --noproxy '*' --fail --silent --show-error --max-time 8 --resolve "
                    out = m.run(curl + shlex.quote(host + ':' + str(shared) + ':192.168.1.2') + ' ' + entry + '://' + host + ':' + str(shared) + '/')
                    expected = ('HOST_VHOST' if header else 'LEGACY_VHOST') + '|' + (header or host) + '|' + ('upstream-sni.home.test' if scheme == 'https' else '')
                    assert out == expected, (out, expected)
                    r['traffic'][mode + '_' + entry] = out
                # Entry Host guard remains entry-only even when backend Host is overridden.
                out = m.run("curl -q --noproxy '*' --silent --max-time 5 -o /dev/null -w '%{http_code}' -H 'Host: backend.home.test' http://192.168.1.2:" + str(shared) + '/', check=False)
                assert out in ('000', '400', '404', '421', '444'), out
                r.setdefault('entry_guard', {})[mode] = out
    except Exception as exc:
        error = repr(exc); r['error'] = error
    finally:
        if lifecycle:
            try:
                r['stopped'] = m.request({'action': 'stop'}); assert r['stopped']['runtime']['cleanup'] == 'confirmed'
            except Exception as exc: r['cleanup_error'] = repr(exc)
        if staged:
            m.run('ubus call service delete ' + shlex.quote(json.dumps({'name': m.NAME + '-backend'})), check=False); time.sleep(2)
            r['cleanup_readback'] = {'runtime': json.loads(m.service('list', {'name': m.NAME})), 'backend': json.loads(m.service('list', {'name': m.NAME + '-backend'}))}
            r['private_processes'] = m.run("ps w | grep -E " + shlex.quote(m.ROOT + '|' + m.RUNTIME) + ' | grep -v grep || true')
            rows = m.run('cat /proc/net/tcp /proc/net/tcp6')
            owned_ports = set(r.get('ports', {}).values())
            for manifest in r.get('listener_manifests', {}).values():
                owned_ports.update(x['port'] for x in manifest)
            r['private_listeners_remaining'] = [line for line in rows.splitlines() if len(line.split()) > 3 and line.split()[3] == '0A' and int(line.split()[1].split(':')[1], 16) in owned_ports]
            if r['cleanup_readback'] == {'runtime': {}, 'backend': {}} and not r['private_processes'] and not r['private_listeners_remaining']:
                m.run('rm -rf ' + m.ROOT + '; test ! -e ' + m.ROOT + '; test ! -e ' + m.RUNTIME)
                r['private_root_removed'] = True
        r['production_unchanged'] = before == m.baseline()
        r['passed'] = not error and not r.get('cleanup_error') and r['production_unchanged'] and r.get('private_root_removed', False) and (args.schema_only or len(r['traffic']) == 8)
        m.EVIDENCE.parent.mkdir(parents=True, exist_ok=True)
        target = m.EVIDENCE.with_name('backend-host-header-schema.json') if args.schema_only else m.EVIDENCE
        if args.legacy_renderer: target = m.EVIDENCE.with_name('backend-host-header-renderer-negative-control.json')
        target.write_text(json.dumps(r, indent=2) + '\n')
    print(json.dumps({k: r.get(k) for k in ('passed', 'schema', 'traffic', 'error', 'cleanup_error', 'production_unchanged', 'private_root_removed')}, indent=2))
    return 0 if r['passed'] else 1

if __name__ == '__main__':
    raise SystemExit(main())
