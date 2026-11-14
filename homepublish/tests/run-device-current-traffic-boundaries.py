"""Remaining valuable legacy contracts on current UUID-private real engines.
No historical provider, production lifecycle, DNS mutation or certificate issuance.
Generated CA/RSA/ECC keys exist solely in the private device root.
"""
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import shlex
import time

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('extensions', HERE / 'run-device-current-traffic-extensions.py')
x = importlib.util.module_from_spec(spec)
spec.loader.exec_module(x)
m = x.m
m.EVIDENCE = m.REPO / 'docs/evidence/lua-store/traffic-current-agent/boundaries.json'
run = x.original_run
triggered = False


def execute():
    r, root, runtime = m.report, m.ROOT, m.RUNTIME
    e = r['remaining_boundaries'] = {'requests': [], 'certificates': [], 'provider_checks': []}
    port = r['ports']['shared']
    config = copy.deepcopy(r['saved']['saved_config'])
    def stop():
        result = m.request({'action': 'stop'})
        assert result['runtime']['cleanup'] == 'confirmed', result
    stop()
    # Test-only inventory root substitution, not an alternate certificate implementation.
    source = run('cat ' + root + '/source/device-integrations.lua')
    assert "local ACME_STATE='/etc/acme'" in source
    source = source.replace("local ACME_STATE='/etc/acme'", "local ACME_STATE='" + root + "/acme'")
    run('cat > ' + root + '/source/device-integrations.lua', source.encode())
    r['substitutions']['device-integrations.lua'] = 'private certificate inventory directory only; native certificate resolver/SAN validation retained'
    cli = "local source='" + root + "/source';package.path=source..'/?.lua;'..package.path;local J=require('product-json');local P=require('product-provider');local C=require('product-controller').new(require('product-system-provider'));local q=J.decode(io.read('*a'));local r;if q.action=='start' then r=C.start(q.revision,q.approved) elseif q.action=='stop' then r=C.stop() else r=assert(P.handle(q,true)) end;print(J.encode(r))"
    run('cat > ' + root + '/cli.lua', cli.encode())
    env = 'HP_ACME_STATE_DIR=' + root + '/acme HP_ACME_LINK_DIR=' + root + '/no-links '
    def request(q):
        return json.loads(run(env + 'lua ' + root + '/cli.lua', json.dumps(q).encode()))
    def launch(c):
        old = request({'action': 'status'})
        s = request({'action': 'save', 'expected_revision': old['saved_revision'], 'config': c})
        assert 'saved_revision' in s, s
        result = request({'action': 'start', 'revision': s['saved_revision'], 'approved': True})
        assert result['runtime']['phase'] == 'running', result
        r['listener_manifest'].extend(json.loads(run('cat ' + runtime + '/listeners.json')))
        e['provider_checks'].append({'saved_revision': s['saved_revision'], 'active_revision': result['active_revision'], 'phase': result['runtime']['phase']})
        return result
    # Both certificates cover two exact domains and a wildcard, but have independent keys/serials.
    script = 'set -e; umask 077; mkdir ' + root + '/acme; cd ' + root + '; '
    script += 'openssl req -x509 -newkey rsa:2048 -nodes -keyout ca.key -out ca.pem -days 2 -subj /CN=HomePublish-Private-Traffic-CA >/dev/null 2>&1; '
    for ident, kind, serial in [('inventory.home.test_rsa', 'rsa', 101), ('inventory.home.test_ecc', 'ecc', 102)]:
        d = 'acme/' + ident
        script += 'mkdir ' + d + '; '
        script += ('openssl genrsa -out ' + d + '/inventory.home.test.key 2048' if kind == 'rsa' else 'openssl ecparam -name prime256v1 -genkey -noout -out ' + d + '/inventory.home.test.key') + ' >/dev/null 2>&1; '
        script += 'openssl req -new -key ' + d + '/inventory.home.test.key -out ' + d + '/req.pem -subj /CN=inventory.home.test >/dev/null 2>&1; '
        script += "printf 'subjectAltName=DNS:a.fixture.home,DNS:b.fixture.home,DNS:*.wild.fixture.home\n' > " + d + '/extensions; '
        script += 'openssl x509 -req -in ' + d + '/req.pem -CA ca.pem -CAkey ca.key -set_serial ' + str(serial) + ' -days 2 -extfile ' + d + '/extensions -out ' + d + '/fullchain.cer >/dev/null 2>&1; '
    run(script)
    # Dedicated backend counts every reached request via access log, including rejects accidentally forwarded.
    backend = 'daemon off; master_process off; pid ' + root + '/backend.pid; error_log ' + root + '/backend.log; events {} http { log_format effect "$request"; access_log ' + root + '/get-effects effect; '
    for p, label in [(r['ports']['web1'], 'BACKEND_A'), (r['ports']['web2'], 'BACKEND_B')]:
        backend += 'server { listen 127.0.0.1:' + str(p) + '; location / { return 200 "' + label + '"; } } '
    backend += '}'
    m.service('delete', {'name': m.NAME + '-backend'}); time.sleep(2)
    run('cat > ' + root + '/backend.conf', backend.encode())
    m.service('set', {'name': m.NAME + '-backend', 'instances': {'web': {'command': ['/usr/libexec/homepublish/nginx', '-p', root + '/', '-c', 'backend.conf']}}})
    time.sleep(1)
    c = copy.deepcopy(config)
    c['default_certificate_ref'] = 'acme:inventory.home.test_rsa'
    template = next(s for s in c['services'] if s['type'] == 'https_proxy')
    c['services'] = []
    for ident, host, ref, p in [('a', 'a.fixture.home', 'acme:inventory.home.test_rsa', r['ports']['web1']), ('b', 'b.fixture.home', 'acme:inventory.home.test_ecc', r['ports']['web2'])]:
        s = copy.deepcopy(template)
        s.update(service_id=ident, name=ident, hostname=host, certificate_mode='override', certificate_ref=ref)
        s['backend'].update(port=p, addressFamily='hostname', host='127.0.0.1.nip.io')
        s['backend'].pop('allowed_ranges', None)
        c['services'].append(s)
    # Two plain HTTP services use the same hostname namespace independently of HTTPS.
    for ident, host, p in [('ha', 'a.fixture.home', r['ports']['web1']), ('hb', 'b.fixture.home', r['ports']['web2'])]:
        s = copy.deepcopy(c['services'][0]); s.update(service_id=ident, name=ident, type='http_proxy', hostname=host)
        s.pop('certificate_ref', None); s.pop('certificate_mode', None); s['backend']['port'] = p
        c['services'].append(s)
    e['hostname_resolution'] = run(env + 'lua -e ' + shlex.quote("package.path='" + root + "/source/?.lua;'..package.path;print(require('product-json').encode(assert(require('device-integrations').resolve('127.0.0.1.nip.io'))))"))
    launch(c)
    e['rendered_configuration'] = run('cat ' + runtime + '/nginx.conf ' + runtime + '/sslh.cfg')
    e['private_source_sha256'] = run('sha256sum ' + root + '/source/device-integrations.lua')
    def count():
        return int(run('wc -l < ' + root + '/get-effects').strip())
    run('touch ' + root + '/get-effects')
    curl = "env -u CURL_CA_BUNDLE -u SSL_CERT_FILE -u SSL_CERT_DIR curl -q --noproxy '*' --silent --show-error --max-time 8 --cacert " + root + '/ca.pem '
    def probe(scheme, sni, host, target='/', version='1.1', accepted=False, marker=None):
        before = count()
        flags = ' --http1.0 ' if version == '1.0' else ' --http1.1 '
        flags += ' -H ' + shlex.quote('Host: ' + host if host is not None else 'Host:')
        cmd = curl + flags + ' --resolve ' + shlex.quote(sni + ':' + str(port) + ':192.168.1.2') + ' --request-target ' + shlex.quote(target) + " -w '\nSTATUS:%{http_code}' " + scheme + '://' + sni + ':' + str(port) + '/'
        out = run(cmd, check=False)
        after = count()
        row = dict(scheme=scheme, sni=sni, host=host, target=target, version=version, expected_accept=accepted, response=out, backend_before=before, backend_after=after)
        e['requests'].append(row)
        assert (after - before) == int(accepted), row
        if accepted:
            assert marker in out and 'STATUS:200' in out, row
        else:
            assert 'STATUS:200' not in out, row
    # Full cross-SNI/Host: only matching pairs may reach either backend.
    for sni in ['a.fixture.home', 'b.fixture.home']:
        for host in ['a.fixture.home', 'b.fixture.home', 'unknown.fixture.home', None]:
            probe('https', sni, host, accepted=sni == host, marker='BACKEND_A' if sni.startswith('a.') else 'BACKEND_B')
        probe('https', sni, None, version='1.0')
        for target_scheme in ['http', 'https', 'HTTP']:
            for target_host in ['a.fixture.home', 'b.fixture.home', 'unknown.fixture.home']:
                for host in ['a.fixture.home', 'b.fixture.home', 'unknown.fixture.home', None]:
                    probe('https', sni, host, target=target_scheme + '://' + target_host + '/')
    for host, marker in [('a.fixture.home', 'BACKEND_A'), ('b.fixture.home', 'BACKEND_B')]:
        for sni in [host, host.upper()]:
            for header in [host, host.upper(), host.title()]:
                probe('https', sni, header, accepted=True, marker=marker)
    # Origin-form HTTP/1.0 without Host must not fall through to a default backend.
    for scheme in ['http', 'https']:
        for host in [None, '', 'a.fixture.home', 'b.fixture.home', 'unknown.fixture.home']:
            good = host in ['a.fixture.home', 'b.fixture.home'] and (scheme == 'http' or host == 'a.fixture.home')
            probe(scheme, 'a.fixture.home', host, version='1.0', accepted=good, marker='BACKEND_B' if host == 'b.fixture.home' else 'BACKEND_A')
        # Absolute-form requests are currently forbidden even when authority matches.
        for target_scheme in ['http', 'https', 'HTTP']:
            for target_host in ['a.fixture.home', 'b.fixture.home', 'unknown.fixture.home']:
                for host in ['a.fixture.home', 'b.fixture.home', 'unknown.fixture.home', None]:
                    probe(scheme, 'a.fixture.home', host, target=target_scheme + '://' + target_host + '/')
        for suffix in [':443', ':65535', ':0', ':65536', ':abc', ':', ':-1', ':0443', '.evil', '@b.fixture.home', '..', '.', 'x']:
            probe(scheme, 'a.fixture.home', 'a.fixture.home' + suffix, accepted=suffix in [':443', ':65535'], marker='BACKEND_A')
    # Assert native resolver reference identity, key type and SAN boundaries directly.
    for ref, kind in [('acme:inventory.home.test_rsa', 'rsa'), ('acme:inventory.home.test_ecc', 'ecc')]:
        for host, allowed in [('a.fixture.home', True), ('b.fixture.home', True), ('one.wild.fixture.home', True), ('wild.fixture.home', False), ('nested.one.wild.fixture.home', False), ('inventory.home.test', False)]:
            code = "package.path='" + root + "/source/?.lua;'..package.path;local I=require('device-integrations');local s,e=I.certificate_source('" + ref + "','" + host + "');print(require('product-json').encode({source=s,error=e}))"
            result = json.loads(run(env + 'lua -e ' + shlex.quote(code)))
            e['certificates'].append(dict(reference=ref, host=host, expected=allowed, result=result))
            assert bool(result.get('source')) == allowed, result
            if allowed:
                assert result['source']['key_type'] == kind
    # Verify actual served independent certificate serials using the private CA and exact SNI.
    for host, serial in [('a.fixture.home', '65'), ('b.fixture.home', '66')]:
        output = run('timeout 10 openssl s_client -connect 192.168.1.2:' + str(port) + ' -servername ' + host + ' -CAfile ' + root + '/ca.pem -verify_return_error -verify_hostname ' + host + ' </dev/null 2>/dev/null | openssl x509 -noout -serial')
        assert output.strip() == 'serial=' + serial, output
        e.setdefault('served_serials', {})[host] = output.strip()
    stop()
    # Shared certificate across distinct exact hosts must preserve backend mapping too.
    shared = copy.deepcopy(c)
    shared['services'] = [s for s in shared['services'] if s['type'] == 'https_proxy']
    for s in shared['services']:
        s['certificate_ref'] = 'acme:inventory.home.test_rsa'
        s['hostname'] = ('one' if s['service_id'] == 'a' else 'two') + '.wild.fixture.home'
    launch(shared)
    for host, marker in [('one.wild.fixture.home', 'BACKEND_A'), ('two.wild.fixture.home', 'BACKEND_B')]:
        probe('https', host, host, accepted=True, marker=marker)
        output = run('timeout 10 openssl s_client -connect 192.168.1.2:' + str(port) + ' -servername ' + host + ' -CAfile ' + root + '/ca.pem -verify_return_error -verify_hostname ' + host + ' </dev/null 2>/dev/null | openssl x509 -noout -serial')
        assert output.strip() == 'serial=65', output
        e.setdefault('shared_served_serials', {})[host] = output.strip()
    stop()
    # Wildcard certificate mapping still uses exact service hostnames (not wildcard routes).
    wc = copy.deepcopy(c)
    wc['services'] = [s for s in wc['services'] if s['type'] == 'https_proxy']
    for s in wc['services']:
        s['hostname'] = ('one' if s['service_id'] == 'a' else 'two') + '.wild.fixture.home'
    launch(wc)
    for host, marker in [('one.wild.fixture.home', 'BACKEND_A'), ('two.wild.fixture.home', 'BACKEND_B')]:
        probe('https', host, host, accepted=True, marker=marker)
    for host in ['wild.fixture.home', 'nested.one.wild.fixture.home', 'unknown.wild.fixture.home']:
        probe('https', host, host)
    stop()
    e['passed'] = True


def hooked(cmd, data=None, check=True):
    global triggered
    out = run(cmd, data, check)
    if not triggered and 'PRIVATE_TCP' in cmd and 's:recv(11)' in cmd:
        triggered = True
        execute()
    return out


if __name__ == '__main__':
    expected = {p.name: hashlib.sha256(p.read_bytes().replace(b'\r\n', b'\n')).hexdigest() for p in m.SOURCE.glob('*.lua')}
    actual = {line.split()[1].rsplit('/', 1)[1]: line.split()[0] for line in run('sha256sum /usr/share/homepublish/*.lua').splitlines()}
    assert expected == actual, 'Installed Lua/source mismatch; refusing fixture lifecycle'
    m.report['installed_normalized_source_sha256'] = actual
    m.run = hooked
    raise SystemExit(m.main())
