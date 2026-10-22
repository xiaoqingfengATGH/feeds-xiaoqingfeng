#!/usr/bin/env python3
"""Local-only actual TLS data plane. No installation, network DNS or router writes."""
import os, pathlib, subprocess, tempfile, socket, ssl, threading, http.server, time
ROOT=pathlib.Path(__file__).resolve().parents[2]
SHARE=ROOT/'homepublish/files/usr/share/homepublish'
LUA=os.environ.get('HOMEPUBLISH_LUA','/home/eric/homestun-sdk-check/local-tools/usr/bin/lua5.1')
SDK=pathlib.Path('/home/eric/homestun-sdk-check/openwrt-sdk-24.10.5-x86-64_gcc-13.3.0_musl.Linux-x86_64/staging_dir/target-x86_64_musl/root-x86')
NGINX=[str(SDK/'lib/ld-musl-x86_64.so.1'),'--library-path',str(SDK/'lib')+':'+str(SDK/'usr/lib'),str(SDK/'usr/sbin/nginx')]
def run(*args):
    r=subprocess.run(args,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
    assert r.returncode==0,r.stderr
    return r
class Handler(http.server.BaseHTTPRequestHandler):
    counts=0
    def do_GET(self):
        self.send_response(200);self.end_headers();self.wfile.write(b'isolated-backend')
    def do_POST(self):
        self.rfile.read(int(self.headers.get('Content-Length',0)))
        Handler.counts+=1
        # Accept side effect then terminate before response: must NOT replay.
        self.connection.shutdown(socket.SHUT_RDWR);self.connection.close()
    def log_message(self,*args): pass
class V6(http.server.ThreadingHTTPServer): address_family=socket.AF_INET6
def freeport():
    with socket.socket() as s:s.bind(('127.0.0.1',0));return s.getsockname()[1]
def connect(addr,port,ctx,sni='service.home'):
    return ctx.wrap_socket(socket.create_connection((addr,port),timeout=3),server_hostname=sni)
def request(addr,port,ctx,host='service.home',post=False):
    with connect(addr,port,ctx) as c:
        c.sendall((('POST' if post else 'GET')+' / HTTP/1.1\r\nHost: '+host+'\r\nConnection: close\r\nContent-Length: 1\r\n\r\nx').encode())
        result=b''
        while True:
            b=c.recv(4096)
            if not b:return result
            result+=b
subprocess.run([LUA,str(ROOT/'homepublish/tests/test-direct.lua'),str(SHARE)],check=True)
owned=[]
with tempfile.TemporaryDirectory(prefix='homepublish-direct-',dir=os.environ.get('TMPDIR','/home/eric/homestun-sdk-check')) as td:
    d=pathlib.Path(td)
    run('openssl','req','-x509','-newkey','rsa:2048','-nodes','-keyout',str(d/'ca.key'),'-out',str(d/'ca.pem'),'-days','1','-subj','/CN=fixture CA')
    run('openssl','req','-newkey','rsa:2048','-nodes','-keyout',str(d/'key.pem'),'-out',str(d/'req.pem'),'-subj','/CN=service.home')
    (d/'ext').write_text('subjectAltName=DNS:service.home\n')
    run('openssl','x509','-req','-in',str(d/'req.pem'),'-CA',str(d/'ca.pem'),'-CAkey',str(d/'ca.key'),'-CAcreateserial','-out',str(d/'cert.pem'),'-days','1','-extfile',str(d/'ext'))
    ctx=ssl.create_default_context(cafile=str(d/'ca.pem'))
    for backend,mode in (('127.0.0.1','literal'),('::1','literal'),('127.0.0.1','hostname')):
        server=(V6 if ':' in backend else http.server.ThreadingHTTPServer)((backend,0),Handler)
        thread=threading.Thread(target=server.serve_forever);thread.start()
        port=freeport();proc=None
        try:
            subprocess.run([LUA,str(ROOT/'homepublish/tests/direct-fixture.lua'),str(SHARE),td,str(port),backend,str(server.server_port),mode],check=True)
            # Production procd start pre-creates the shared temp spool; mirror it.
            (pathlib.Path('/tmp/homepublish-tmp')).mkdir(parents=True,exist_ok=True)
            tested=run(*NGINX,'-p',td+'/', '-c',str(d/'nginx.conf'),'-t');print(tested.stderr.strip())
            proc=subprocess.Popen(NGINX+['-p',td+'/', '-c',str(d/'nginx.conf')],stdout=subprocess.PIPE,stderr=subprocess.PIPE);owned.append(proc.pid)
            end=time.monotonic()+5
            while True:
                try:
                    with connect('127.0.0.1',port,ctx):pass
                    break
                except (OSError,ssl.SSLError):
                    assert proc.poll() is None,proc.communicate()
                    if time.monotonic()>end:raise
                    time.sleep(.02)
            for ingress in ('127.0.0.1','::1'):
                result=request(ingress,port,ctx);assert b'200 OK' in result and b'isolated-backend' in result,result
                print('PASS ingress '+ingress+' -> backend '+backend+' TLS verified CA/SAN')
                before=Handler.counts;result=request(ingress,port,ctx,post=True);assert b'502' in result,result
                time.sleep(.05);assert Handler.counts==before+1,'POST replay'
                assert request(ingress,port,ctx,host='unknown.home')==b'','unknown Host reached backend'
                try:
                    with connect(ingress,port,ctx,'unknown.home'):pass
                except ssl.SSLError:pass
                else:raise AssertionError('unknown SNI accepted')
            print('PASS POST exactly once after accepted side effect; unknown Host/SNI rejected')
        finally:
            if proc:
                proc.terminate()
                try:proc.communicate(timeout=5)
                except subprocess.TimeoutExpired:proc.kill();proc.communicate(timeout=5)
                assert proc.poll() is not None
            server.shutdown();server.server_close();thread.join(timeout=5);assert not thread.is_alive()
            for addr in ('127.0.0.1','::1'):
                try:
                    c=socket.create_connection((addr,port),timeout=.2);c.close()
                except OSError:pass
                else:raise AssertionError('owned listener remains')
    for pid in owned:assert not pathlib.Path('/proc',str(pid)).exists(),'owned process remains'
assert not pathlib.Path(td).exists(),'temporary TLS files remain'
print('PASS cleanup: owned processes/listeners absent, temporary CA/key/cert removed')
