"""Current real-device extensions for retired direct/shared and unsafe P5 fixtures.
Uses the UUID-private HTTP traffic runner; never invokes old fixed-root writers.
No production writes, firewall operations, package installation or browser access.
"""
import copy
import importlib.util
import json
from pathlib import Path
import shlex
import subprocess
import time

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('private_http', HERE / 'run-device-http-traffic.py')
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
m.EVIDENCE = m.REPO / 'docs/evidence/lua-store/traffic-current-agent/extensions.json'
original_run = m.run
original_baseline = m.baseline
triggered = False


def protected_baseline():
    base = original_baseline()
    status = json.loads(original_run("ubus call homepublish status '{}'"))
    stable = {k: status.get(k) for k in ['saved_revision', 'active_revision', 'intent_revision', 'desired_state']}
    stable['runtime'] = {k: status.get('runtime', {}).get(k) for k in ['phase', 'generation', 'active_verified']}
    stable['runtime_service'] = json.loads(original_run("ubus call service list '{\"name\":\"homepublish-runtime\"}'"))
    stable['generated_hashes'] = original_run('sha256sum /tmp/homepublish-runtime/nginx.conf /tmp/homepublish-runtime/sslh.cfg')
    m.report.setdefault('production_snapshots', []).append(stable)
    return base + json.dumps(stable, sort_keys=True)


m.baseline = protected_baseline


def extend():
    r = m.report
    r['extensions'] = {'matrix': [], 'boundary': [], 'lifecycle': []}
    e = r['extensions']
    root, runtime, name = m.ROOT, m.RUNTIME, m.NAME
    # Fresh CLI supports Apply through the current controller, not legacy adapter.
    cli = "local source='" + root + "/source';package.path=source..'/?.lua;'..package.path;local J=require('product-json');local P=require('product-provider');local C=require('product-controller').new(require('product-system-provider'));local q=J.decode(io.read('*a'));local r;if q.action=='start' then r=C.start(q.revision,q.approved) elseif q.action=='apply' then r=C.apply(q.revision,q.approved) elseif q.action=='stop' then r=C.stop() else r=assert(P.handle(q,true)) end;print(J.encode(r))"
    original_run('cat > ' + root + '/cli.lua', cli.encode())
    config = copy.deepcopy(r['saved']['saved_config'])
    ports = r['ports']
    shared, dedicated = ports['shared'], ports['dedicated']
    # Keep all internal allocation records for final LISTEN closure verification.
    manifests = list(r['listener_manifest'])

    def capture():
        manifests.extend(json.loads(original_run('cat ' + runtime + '/listeners.json')))
        r['listener_manifest'] = manifests

    def save(c):
        old = m.request({'action': 'status'})
        s = m.request({'action': 'save', 'expected_revision': old['saved_revision'], 'config': c})
        assert 'saved_revision' in s, s
        return s

    def launch(c):
        s = save(c)
        a = m.request({'action': 'start', 'revision': s['saved_revision'], 'approved': True})
        assert a['runtime']['phase'] == 'running', a
        capture()
        return a

    def stop():
        a = m.request({'action': 'stop'})
        assert a['runtime']['cleanup'] == 'confirmed', a

    curl = "env -u CURL_CA_BUNDLE -u SSL_CERT_FILE -u SSL_CERT_DIR curl -q --noproxy '*' --silent --show-error --max-time 8 "

    def web(host='one.home.test', scheme='http', addr='192.168.1.2', extra=''):
        endpoint = '[' + addr + ']' if ':' in addr else addr
        return original_run(curl + '--resolve ' + shlex.quote(host + ':' + str(shared) + ':' + endpoint) + ' ' + extra + ' ' + scheme + '://' + host + ':' + str(shared) + '/', check=False)

    # Current save vs Apply semantics: source backends already return distinct A/B.
    before = m.request({'action': 'status'})
    c = copy.deepcopy(config)
    next(s for s in c['services'] if s['service_id'] == 'one')['backend']['port'] = ports['web2']
    saved = save(c)
    after_save = m.request({'action': 'status'})
    assert after_save['active_revision'] == before['active_revision']
    assert web().startswith('HTTP_ONE|')
    applied = m.request({'action': 'apply', 'revision': saved['saved_revision'], 'approved': True})
    assert applied['runtime']['phase'] == 'running', applied
    capture()
    assert web().startswith('HTTP_TWO|')
    e['lifecycle'].append({'saved_revision': saved['saved_revision'], 'active_before': before['active_revision'], 'active_after_save': after_save['active_revision'], 'active_after_apply': applied['active_revision'], 'traffic': ['HTTP_ONE after Save', 'HTTP_TWO after Apply']})

    # Migrate direct-boundary's still-current single-host authority contracts.
    for scheme, host in [('http', 'one.home.test'), ('https', 'home.iwonderful.top')]:
        for authority, accepted in [(host.upper(), True), (host + ':443', True), (host + ':65535', True), (host + ':0', False), (host + ':65536', False), (host + ':0443', False), (host + ':abc', False), (host + '.evil', False), ('two.home.test' if scheme == 'https' else 'unknown.home.test', False)]:
            out = web(host, scheme, extra="-o /dev/null -w '%{http_code}' -H " + shlex.quote('Host: ' + authority))
            assert (out == '200') == accepted, (scheme, authority, out)
            e['boundary'].append({'scheme': scheme, 'authority': authority, 'accepted': accepted, 'status': out})
        for target in ['http://one.home.test/', 'https://home.iwonderful.top/']:
            out = web(host, scheme, extra="-o /dev/null -w '%{http_code}' --request-target " + shlex.quote(target))
            assert out != '200', out
            e['boundary'].append({'scheme': scheme, 'absolute_target': target, 'status': out})
    out = original_run("timeout 10 openssl s_client -connect 192.168.1.2:" + str(shared) + " -servername unknown.home.test </dev/null 2>&1", check=False)
    assert 'BEGIN CERTIFICATE' not in out and ('error' in out.lower() or 'no peer certificate' in out.lower()), out
    e['unknown_sni'] = out
    stop()

    # Migrate direct.py's accepted-side-effect/no-replay contract to current engines.
    post_port = int(original_run("lua -e 'local n=require(\"nixio\");local s=assert(n.socket(\"inet\",\"stream\"));assert(s:bind(\"127.0.0.1\",0));local _,p=s:getsockname();print(p)'"))
    ports['post'] = post_port
    post_lua = "local length=0;while true do local l=io.read('*l');if not l or l=='\\r' or l=='' then break end;local n=l:lower():match('^content%-length:%s*(%d+)');if n then length=tonumber(n) end end;if length>0 then assert(io.read(length)) end;local f=assert(io.open('" + root + "/post-effects','a'));f:write('POST\\n');f:close()"
    original_run('cat > ' + root + '/post.lua', post_lua.encode())
    instances = {k: {'command': v['command']} for k, v in r['backend_readback'][name + '-backend']['instances'].items()}
    instances['post'] = {'command': ['/usr/bin/socat', 'TCP4-LISTEN:' + str(post_port) + ',bind=127.0.0.1,reuseaddr,fork', 'EXEC:/usr/bin/lua ' + root + '/post.lua']}
    m.service('set', {'name': name + '-backend', 'instances': instances})
    time.sleep(1)
    c = copy.deepcopy(config)
    for svc in c['services']:
        if svc['type'] in ['http_proxy', 'https_proxy']:
            svc['backend']['port'] = post_port
    launch(c)
    for scheme, host in [('http', 'one.home.test'), ('https', 'home.iwonderful.top')]:
        out = web(host, scheme, extra="-o /dev/null -w '%{http_code}' --data x")
        assert out == '502', out
    effects = original_run('cat ' + root + '/post-effects').splitlines()
    assert effects == ['POST', 'POST'], effects
    e['post_no_replay'] = {'http_status': '502', 'https_status': '502', 'requests': 2, 'accepted_side_effects': len(effects)}
    stop()

    # A dedicated private authenticated Dropbear replaces historical banner-only proof.
    original_run('umask 077; mkdir ' + root + '/auth; dropbearkey -t ed25519 -f ' + root + '/auth/host >/dev/null 2>&1; dropbearkey -t ed25519 -f ' + root + '/auth/client > ' + root + '/auth/client.pub 2>/dev/null; ' + "sed -n '/^ssh-ed25519 /p' " + root + '/auth/client.pub > ' + root + '/auth/authorized_keys; chmod 600 ' + root + '/auth/*')
    cert = json.loads(original_run('lua -e ' + shlex.quote("package.path='" + root + "/source/?.lua;'..package.path;print(require('product-json').encode(assert(require('device-integrations').certificate_source('acme:home.iwonderful.top','home.iwonderful.top'))))")))
    backend = 'daemon off; master_process off; pid ' + root + '/backend.pid; error_log ' + root + '/backend.log; events {} http { access_log off; '
    for addr in ['127.0.0.1', '[fd89:878e:a47f::1]']:
        backend += 'server { listen ' + addr + ':' + str(ports['web1']) + '; location / { return 200 "MATRIX_WEB"; } } '
        backend += 'server { listen ' + addr + ':' + str(ports['tls']) + ' ssl; ssl_certificate ' + cert['certificate'] + '; ssl_certificate_key ' + cert['key'] + '; location / { return 200 "MATRIX_TLS"; } } '
    backend += '}'
    m.service('delete', {'name': name + '-backend'})
    time.sleep(2)
    original_run('cat > ' + root + '/backend.conf', backend.encode())
    m.service('set', {'name': name + '-backend', 'instances': {
        'web': {'command': ['/usr/libexec/homepublish/nginx', '-p', root + '/', '-c', 'backend.conf']},
        'ssh': {'command': ['/usr/sbin/dropbear', '-F', '-E', '-s', '-j', '-k', '-r', root + '/auth/host', '-D', root + '/auth', '-p', '127.0.0.1:' + str(ports['ssh']), '-p', '[fd89:878e:a47f::1]:' + str(ports['ssh']), '-P', root + '/auth/pid', '-c', 'printf PRIVATE_SSH_AUTH']},
        'raw4': {'command': ['/usr/bin/socat', 'TCP4-LISTEN:' + str(ports['raw']) + ',bind=127.0.0.1,reuseaddr,fork', 'EXEC:/bin/cat']},
        'raw6': {'command': ['/usr/bin/socat', 'TCP6-LISTEN:' + str(ports['raw']) + ',bind=[fd89:878e:a47f::1],ipv6only=1,reuseaddr,fork', 'EXEC:/bin/cat']}}})
    time.sleep(2)
    e['backend_readback'] = json.loads(m.service('list', {'name': name + '-backend'}))
    cases = [(i, b, ['http_proxy', 'https_proxy', 'tls_passthrough', 'ssh', 'tcp_forward']) for i in ['ipv4', 'ipv6'] for b in ['ipv4', 'ipv6']]
    cases += [('ipv6', 'ipv6', types + ['tcp_forward']) for types in [['tls_passthrough'], ['ssh'], ['tls_passthrough', 'ssh']]]
    for ingress, backfam, types in cases:
        c = copy.deepcopy(config)
        addr = '192.168.1.2' if ingress == 'ipv4' else 'fd89:878e:a47f::1'
        c['access_profile']['listeners'][0].update(family=ingress, address=addr)
        c['services'] = [s for s in c['services'] if s['type'] in types and s['service_id'] != 'two']
        for s in c['services']:
            s['backend'].update(addressFamily=backfam, host='127.0.0.1' if backfam == 'ipv4' else 'fd89:878e:a47f::1')
            s['backend'].pop('allowed_ranges', None)
        if 'https_proxy' not in types:
            c.pop('default_certificate_ref', None)
        a = launch(c)
        results = {}
        for typ, scheme, host, marker in [('http_proxy', 'http', 'one.home.test', 'MATRIX_WEB'), ('https_proxy', 'https', 'home.iwonderful.top', 'MATRIX_WEB')]:
            if typ in types:
                out = web(host, scheme, addr)
                assert out == marker, (typ, out)
                results[typ] = out
        endpoint = '[' + addr + ']' if ':' in addr else addr
        if 'tls_passthrough' in types:
            out = original_run("printf 'GET / HTTP/1.0\\r\\nHost: opaque.home.test\\r\\n\\r\\n' | timeout 12 openssl s_client -quiet -verify_return_error -verify_hostname home.iwonderful.top -connect " + endpoint + ':' + str(shared) + ' -servername opaque.home.test')
            assert 'MATRIX_TLS' in out, out
            results['tls_passthrough'] = 'MATRIX_TLS; CA/hostname verified as home.iwonderful.top, routing SNI opaque.home.test'
        if 'ssh' in types:
            out = original_run('dbclient -y -y -i ' + root + '/auth/client -p ' + str(shared) + ' root@' + addr + ' ignored')
            assert out == 'PRIVATE_SSH_AUTH', out
            results['ssh'] = out
        code = "local n=require('nixio');local s=assert(n.socket('" + ('inet6' if ingress == 'ipv6' else 'inet') + "','stream'));s:setopt('socket','rcvtimeo',8);assert(s:connect('" + addr + "'," + str(dedicated) + "));assert(s:send('private_tcp')==11);assert(s:recv(11)=='private_tcp');s:close();print('TCP_ECHO')"
        results['tcp_forward'] = original_run('lua -e ' + shlex.quote(code)).strip()
        if not e['matrix']:
            held_lua = "local n=require('nixio');local sockets={};for _,p in ipairs({" + str(dedicated) + ',' + str(shared) + "}) do local s=assert(n.socket('inet','stream'));assert(s:connect('192.168.1.2',p));s:setopt('socket','rcvtimeo',20);if p==" + str(dedicated) + " then assert(s:send('held')==4);assert(s:recv(4)=='held') else s:send('SSH-2.0-PrivateHeld');assert(s:recv(256):match('SSH%-2%.0')) end;sockets[#sockets+1]=s end;local f=assert(io.open('" + root + "/held.ready','w'));f:write('ready');f:close();local drained=0;for _,s in ipairs(sockets) do local closed=false;for i=1,128 do local v,err=s:recv(4096);if v=='' or (v==nil and err==104) then closed=true;break end;assert(v,'timeout waiting Stop EOF');drained=drained+#v end;assert(closed,'held connection remains');s:close() end;print('TCP_SSH_STOP_EOF buffered='..drained)"
            original_run('cat > ' + root + '/held.lua', held_lua.encode())
            held = subprocess.Popen(m.SSH + ['lua ' + root + '/held.lua'], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            try:
                original_run('for i in 1 2 3 4 5; do test -e ' + root + '/held.ready && exit 0; sleep 1; done; exit 1')
                stop()
                stdout, stderr = held.communicate(timeout=30)
                assert held.returncode == 0, (stdout, stderr)
                e['held_stop_eof'] = stdout.decode().strip()
            finally:
                if held.poll() is None:
                    held.kill()
                    held.communicate()
        else:
            stop()
        e['matrix'].append({'ingress': ingress, 'backend': backfam, 'types': types, 'traffic': results, 'cleanup': 'confirmed'})
    assert len(e['matrix']) == 7
    e['passed'] = True


def hooked_run(cmd, data=None, check=True):
    global triggered
    out = original_run(cmd, data, check)
    if not triggered and "PRIVATE_TCP" in cmd and "s:recv(11)" in cmd:
        triggered = True
        extend()
    return out


if __name__ == '__main__':
    m.run = hooked_run
    raise SystemExit(m.main())
