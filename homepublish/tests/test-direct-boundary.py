#!/usr/bin/env python3
"""Real loopback TLS authority boundary; two certificates/backends, no installs."""
import http.server
import os
import pathlib
import socket
import ssl
import subprocess
import sys
import tempfile
import threading
import time

ROOT = pathlib.Path(__file__).resolve().parents[2]
SHARE = ROOT / 'homepublish/files/usr/share/homepublish'
LUA = os.environ.get('HOMEPUBLISH_LUA', '/home/eric/homestun-sdk-check/local-tools/usr/bin/lua5.1')
SDK = pathlib.Path('/home/eric/homestun-sdk-check/openwrt-sdk-24.10.5-x86-64_gcc-13.3.0_musl.Linux-x86_64/staging_dir/target-x86_64_musl/root-x86')
NGINX = [str(SDK / 'lib/ld-musl-x86_64.so.1'), '--library-path', str(SDK / 'lib') + ':' + str(SDK / 'usr/lib'), str(SDK / 'usr/sbin/nginx')]
MODE = sys.argv[1] if len(sys.argv) > 1 else 'all'
HOSTS = ('service.home', 'second.home')


def run(*args):
    p = subprocess.run(args, capture_output=True, text=True)
    assert p.returncode == 0, p.stderr


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.server.gets += 1
        self.send_response(200)
        self.end_headers()
        self.wfile.write(self.server.marker)

    def log_message(self, *args):
        pass


class V6(http.server.ThreadingHTTPServer):
    address_family = socket.AF_INET6


def connect(addr, port, ctx, sni):
    return ctx.wrap_socket(socket.create_connection((addr, port), timeout=3), server_hostname=sni)


def wire(addr, port, ctx, sni, host, target='/', version='HTTP/1.1'):
    with connect(addr, port, ctx, sni) as c:
        c.sendall(('GET ' + target + ' ' + version + '\r\n' + ('' if host is None else 'Host: ' + host + '\r\n') + 'Connection: close\r\n\r\n').encode())
        data = b''
        while True:
            part = c.recv(4096)
            if not part:
                return data
            data += part


owned = []
with tempfile.TemporaryDirectory(prefix='homepublish-boundary-', dir=os.environ.get('TMPDIR', '/home/eric/homestun-sdk-check')) as td:
    d = pathlib.Path(td)
    run('openssl', 'req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-keyout', str(d/'ca.key'), '-out', str(d/'ca.pem'), '-days', '1', '-subj', '/CN=boundary CA')
    for host in HOSTS:
        run('openssl', 'req', '-newkey', 'rsa:2048', '-nodes', '-keyout', str(d/(host+'.key')), '-out', str(d/'req'), '-subj', '/CN='+host)
        (d/'ext').write_text('subjectAltName=DNS:'+host+'\n')
        run('openssl', 'x509', '-req', '-in', str(d/'req'), '-CA', str(d/'ca.pem'), '-CAkey', str(d/'ca.key'), '-CAcreateserial', '-out', str(d/(host+'.pem')), '-days', '1', '-extfile', str(d/'ext'))
    ctx = ssl.create_default_context(cafile=str(d/'ca.pem'))
    assert ctx.check_hostname and ctx.verify_mode == ssl.CERT_REQUIRED
    for backend in ('127.0.0.1', '::1'):
        servers = []
        threads = []
        proc = None
        with socket.socket() as s:
            s.bind(('127.0.0.1', 0)); port = s.getsockname()[1]
        try:
            for host in HOSTS:
                server = (V6 if ':' in backend else http.server.ThreadingHTTPServer)((backend, 0), Handler)
                server.gets = 0; server.marker = host.encode()
                servers.append(server)
                t = threading.Thread(target=server.serve_forever); t.start(); threads.append(t)
            run(LUA, str(ROOT/'homepublish/tests/direct-boundary-fixture.lua'), str(SHARE), td, str(port), backend, *(str(s.server_port) for s in servers))
            # Production procd start pre-creates the shared temp spool; mirror it.
            pathlib.Path('/tmp/homepublish-tmp').mkdir(parents=True, exist_ok=True)
            run(*NGINX, '-p', td+'/', '-c', str(d/'nginx.conf'), '-t')
            proc = subprocess.Popen(NGINX+['-p', td+'/', '-c', str(d/'nginx.conf')], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            owned.append(proc.pid)
            deadline = time.monotonic()+5
            while True:
                try:
                    with connect('127.0.0.1', port, ctx, HOSTS[0]): pass
                    break
                except (OSError, ssl.SSLError):
                    assert proc.poll() is None, proc.communicate()
                    if time.monotonic() > deadline: raise
                    time.sleep(.02)
            for ingress in ('127.0.0.1', '::1'):
                def probe(sni, host, target='/', accepted=None, version='HTTP/1.1'):
                    before = [s.gets for s in servers]
                    response = wire(ingress, port, ctx, sni, host, target, version)
                    delta = [s.gets-b for s, b in zip(servers, before)]
                    expected = [int(accepted == h) for h in HOSTS]
                    assert delta == expected, (MODE, ingress, backend, sni, host, target, delta, expected, response)
                    if accepted:
                        assert b'200 OK' in response and accepted.encode() in response, response
                    else:
                        assert b'200 OK' not in response, response
                for host in HOSTS:
                    probe(host, host, accepted=host)
                before = [s.gets for s in servers]
                for unknown in ('unknown.home', 'SERVICEXHOME', 'service.home.evil'):
                    try:
                        with connect(ingress, port, ctx, unknown): pass
                    except ssl.SSLError: pass
                    else: raise AssertionError('unknown SNI handshake accepted')
                assert [s.gets for s in servers] == before
                for sni in HOSTS:
                    for host in (*HOSTS, 'unknown.home', None):
                        probe(sni, host, accepted=sni if host == sni else None)
                    probe(sni, None, version='HTTP/1.0')
                    for authority in (*HOSTS, 'unknown.home'):
                        for host in (*HOSTS, 'unknown.home', None):
                            for scheme in ('http://', 'https://', 'HTTP://'):
                                probe(sni, host, scheme+authority+'/')
                if MODE in ('case', 'all'):
                    for host in HOSTS:
                        for sni in (host, host.upper()):
                            for header in (host, host.upper(), host.title()):
                                probe(sni, header, accepted=host)
                    print('PASS case-insensitive SNI/Host with CA/SAN verification', ingress, backend)
                if MODE in ('port', 'all'):
                    for host in HOSTS:
                        for header in (host+':'+str(port), host.upper()+':'+str(port)):
                            probe(host.upper(), header, accepted=host)
                        # 01dd536: authority port is syntax, not listener
                        # authorization (NAT remap); any valid 1-65535 is
                        # accepted, leading zeros and junk stay rejected.
                        for suffix in (':443',):
                            probe(host, host+suffix, accepted=host)
                        for suffix in (':0', ':65536', ':abc', ':', ':-1', ':0'+str(port), '.evil', '@second.home', '..', '.'):
                            probe(host, host+suffix)
                        for lookalike in (host.replace('.', 'x'), host+'x', 'x'+host):
                            probe(host, lookalike)
                    print('PASS actual listener Host port; malformed/foreign ports and names zero GET effects', ingress, backend)
                print('PASS absolute/origin unknown/cross-service zero GET effects', ingress, backend)
        finally:
            if proc:
                proc.terminate()
                try: proc.communicate(timeout=5)
                except subprocess.TimeoutExpired: proc.kill(); proc.communicate(timeout=5)
                assert proc.poll() is not None
            for s in servers: s.shutdown(); s.server_close()
            for t in threads: t.join(timeout=5); assert not t.is_alive()
            for addr in ('127.0.0.1', '::1'):
                try:
                    c = socket.create_connection((addr, port), timeout=.2); c.close()
                except OSError: pass
                else: raise AssertionError('owned listener remains')
    for pid in owned: assert not pathlib.Path('/proc', str(pid)).exists()
assert not pathlib.Path(td).exists()
print('PASS boundary cleanup: processes/listeners absent, temporary certificates removed')
