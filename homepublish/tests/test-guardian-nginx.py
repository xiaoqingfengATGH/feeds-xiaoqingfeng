#!/usr/bin/env python3
"""D2b2 genuine RED acceptance gate, not an expected-failure green regression.
Cached fixed Nginx; no installs, production helpers, DNS, firewall or activation.
The fixture currently exposes channel errors and must remain failing until a
kernel-enforced, provider-specific foreign-FD exclusion is implemented.
"""
import array, hashlib, http.server, json, os, pathlib, signal, socket, ssl
import subprocess, tempfile, threading, time
ROOT=pathlib.Path(__file__).resolve().parents[2]
SRC=ROOT/'homepublish/src'
SDK=pathlib.Path('/home/eric/homestun-sdk-check/openwrt-sdk-24.10.5-x86-64_gcc-13.3.0_musl.Linux-x86_64/staging_dir/target-x86_64_musl/root-x86')
LUA='/home/eric/homestun-sdk-check/local-tools/usr/bin/lua5.1'
SHARE=ROOT/'homepublish/files/usr/share/homepublish'
EVIDENCE=pathlib.Path(os.environ.get('HP_D2B2_EVIDENCE','/home/eric/homestun-sdk-check/d2b2-nginx-evidence'))
EVIDENCE.mkdir(parents=True,exist_ok=True)
results=[]
owned=set()
def children(pid):
    found=[]
    for p in pathlib.Path('/proc').glob('[0-9]*/status'):
        try:
            if int(p.read_text().split('PPid:\t')[1].splitlines()[0])==pid:found.append(int(p.parent.name))
        except (OSError,ValueError,IndexError):pass
    return sorted(found)
def wait_for(fn,seconds=3):
    end=time.monotonic()+seconds
    while time.monotonic()<end:
        try:
            v=fn()
            if v:return v
        except (OSError,ssl.SSLError):pass
        time.sleep(.02)
    raise AssertionError('bounded condition not reached')
def compile_fixture(d):
    vals={'HP_NGINX_LOADER':SDK/'lib/ld-musl-x86_64.so.1',
          'HP_NGINX_EXEC':SDK/'usr/sbin/nginx',
          'HP_NGINX_LIBS':str(SDK/'lib')+':'+str(SDK/'usr/lib'),
          'HP_NGINX_PREFIX':d,'HP_FOREIGN_SOCKET':d/'foreign.sock'}
    subprocess.run(['cc','-std=c11','-Wall','-Wextra','-Werror','-DHP_GUARD_TEST','-I'+str(SRC),
                    *['-D'+k+'='+json.dumps(str(v)) for k,v in vals.items()],
                    str(SRC/'renewable-guard.c'),str(ROOT/'homepublish/tests/guardian-nginx-fixture.c'),
                    '-o',str(d/'fixture')],check=True)
    return d/'fixture'
class Backend(http.server.BaseHTTPRequestHandler):
    def log_message(self,*args):pass
    def do_GET(self):
        self.send_response(200);self.send_header('Content-Type','text/plain');self.send_header('X-Accel-Buffering','no');self.end_headers()
        if self.path=='/stream':
            for i in range(500):
                try:self.wfile.write(('tick-%d\n'%i).encode());self.wfile.flush()
                except (BrokenPipeError,ConnectionResetError):break
                time.sleep(.04)
        else:self.wfile.write(b'guarded-backend')
class Server(http.server.ThreadingHTTPServer):daemon_threads=True
def connect(addr,port,ctx):
    return ctx.wrap_socket(socket.create_connection((addr,port),timeout=.3),server_hostname='service.home')
def request(addr,port,ctx):
    with connect(addr,port,ctx) as s:
        s.sendall(b'GET / HTTP/1.0\r\nHost: service.home\r\n\r\n')
        data=b''
        while True:
            v=s.recv(4096)
            if not v:return data
            data+=v
def certify(d):
    def run(*cmd):subprocess.run(cmd,check=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
    run('openssl','req','-x509','-newkey','rsa:2048','-nodes','-keyout',str(d/'ca.key'),'-out',str(d/'ca.pem'),'-days','1','-subj','/CN=fixture CA')
    run('openssl','req','-newkey','rsa:2048','-nodes','-keyout',str(d/'key.pem'),'-out',str(d/'req.pem'),'-subj','/CN=service.home')
    (d/'ext').write_text('subjectAltName=DNS:service.home\n')
    run('openssl','x509','-req','-in',str(d/'req.pem'),'-CA',str(d/'ca.pem'),'-CAkey',str(d/'ca.key'),'-CAcreateserial','-out',str(d/'cert.pem'),'-days','1','-extfile',str(d/'ext'))
    return ssl.create_default_context(cafile=str(d/'ca.pem'))
def assert_dead(pids,port,ctx):
    # These assertions run before any fallback kill or fixture removal.
    live=[p for p in pids if pathlib.Path('/proc',str(p)).exists()]
    assert not live,('owned process remains before fallback',live)
    for addr in ('127.0.0.1','::1'):
        try:
            with socket.create_connection((addr,port),timeout=.2):pass
        except OSError:pass
        else:raise AssertionError('listener remains before fallback')
def foreign_test(d,exe):
    listener=socket.socket(socket.AF_UNIX,socket.SOCK_STREAM);listener.bind(str(d/'foreign.sock'));listener.listen()
    sentinel=d/'foreign.txt';sentinel.write_text('foreign-preserved')
    errors=[];sent=[]
    def sender():
        try:
            listener.settimeout(3)
            with listener.accept()[0] as s, sentinel.open('rb') as f:
                sent.append(s.sendmsg([b'F'],[(socket.SOL_SOCKET,socket.SCM_RIGHTS,array.array('i',[f.fileno()]))]))
        except Exception as e:errors.append(repr(e))
    th=threading.Thread(target=sender);th.start()
    p=subprocess.run([str(exe),'foreign','0'],capture_output=True,text=True,timeout=6)
    th.join(4);listener.close()
    assert not th.is_alive() and not errors,(errors,p.stdout,p.stderr)
    assert p.returncode==0 and 'recvmsg rc=-1 errno=1' in p.stdout,(p.returncode,p.stdout,p.stderr)
    assert sent==[1] and sentinel.read_text()=='foreign-preserved',sent
    guardian=int(p.stdout.split('guardian=')[1].splitlines()[0]);assert not pathlib.Path('/proc',str(guardian)).exists()
    print('PASS real external pathname UNIX SCM_RIGHTS queued; guarded recvmsg EPERM',flush=True)
    results.append({'case':'foreign-SCM_RIGHTS','queued_bytes':sent,'recvmsg_errno':1,'guardian_absent':True})
try:
    with tempfile.TemporaryDirectory(prefix='d2b2-nginx-',dir=os.environ.get('TMPDIR','/home/eric/homestun-sdk-check')) as td:
        base=pathlib.Path(td);ctx=certify(base)
        back=Server(('127.0.0.1',0),Backend);th=threading.Thread(target=back.serve_forever);th.start()
        try:
            probe=base/'probe';probe.mkdir();foreign_test(probe,compile_fixture(probe))
            for fault in ('renew-rebuild','temporary','controller-kill','controller-stop','guardian-kill','guardian-stop','watchdog-kill','watchdog-stop'):
                d=base/fault;d.mkdir()
                for n in ('cert.pem','key.pem'):(d/n).write_bytes((base/n).read_bytes())
                with socket.socket() as s:s.bind(('127.0.0.1',0));port=s.getsockname()[1]
                subprocess.run([LUA,str(ROOT/'homepublish/tests/direct-fixture.lua'),str(SHARE),str(d),str(port),'127.0.0.1',str(back.server_port),'literal'],check=True,stdout=subprocess.PIPE)
                config=(d/'nginx.conf').read_text()
                config=config.replace('worker_processes 1;','worker_processes 2;')
                assert 'worker_processes 2;' in config,config
                config=config.replace('error_log stderr warn;',f'error_log {d}/error.log notice;')
                # Renderer may use a file log; use explicit final directive without relaxing TLS rules.
                import re
                config=re.sub(r'error_log [^;]+;',f'error_log {d}/error.log notice;',config)
                (d/'nginx.conf').write_text(config)
                exe=compile_fixture(d)
                started=time.monotonic();p=subprocess.Popen([str(exe),'nginx','1200' if fault=='temporary' else '0'],stdout=subprocess.PIPE,text=True)
                owned.add(p.pid);tracked={p.pid};stream=None
                try:
                    line=p.stdout.readline().strip();assert 'rc=0' in line,line
                    guardian=int(line.split('guardian=')[1]);tracked.add(guardian)
                    wait_for(lambda:b'guarded-backend' in request('127.0.0.1',port,ctx))
                    assert b'guarded-backend' in request('::1',port,ctx)
                    watchdog=children(guardian)[0];master=children(watchdog)[0];tracked.update([watchdog,master])
                    workers=wait_for(lambda:children(master) if len(children(master))==2 else None);tracked.update(workers);owned.update(tracked)
                    stream=connect('127.0.0.1',port,ctx);stream.sendall(b'GET /stream HTTP/1.0\r\nHost: service.home\r\n\r\n')
                    wait_for(lambda:b'tick-' in stream.recv(4096))
                    record={'case':fault,'master':master,'workers':workers,'port':port,'TLS_v4_v6':True}
                    if fault=='renew-rebuild':
                        os.kill(workers[0],signal.SIGKILL)
                        new=wait_for(lambda:children(master) if len(children(master))==2 and workers[0] not in children(master) else None)
                        tracked.update(new);owned.update(new);record['rebuilt_workers']=new
                        # The deliberately killed worker may own the first stream.
                        # Start a new measured stream only after worker rebuild.
                        stream.close();stream=connect('127.0.0.1',port,ctx)
                        stream.sendall(b'GET /stream HTTP/1.0\r\nHost: service.home\r\n\r\n')
                        wait_for(lambda:b'tick-' in stream.recv(4096))
                        end=time.monotonic()+2
                        while time.monotonic()<end:
                            assert b'guarded-backend' in request('127.0.0.1',port,ctx)
                            assert b'tick-' in stream.recv(4096),'stream died during renewal'
                            time.sleep(.12)
                        assert children(watchdog)==[master];record['same_master_multiple_windows']=True
                        os.kill(p.pid,signal.SIGTERM)
                    elif fault!='temporary':
                        target={'controller':p.pid,'guardian':guardian,'watchdog':watchdog}[fault.split('-')[0]]
                        os.kill(target,signal.SIGKILL if fault.endswith('kill') else signal.SIGSTOP)
                    fault_at=time.monotonic();deadline=fault_at+2
                    closed=False;stream.settimeout(.15)
                    while time.monotonic()<deadline:
                        try:
                            if not stream.recv(4096):closed=True;break
                        except (ConnectionResetError,ssl.SSLError):closed=True;break
                        except socket.timeout:pass
                    assert closed,'existing TLS stream not closed'
                    record['closure_ms_since_start']=round((time.monotonic()-started)*1000)
                    record['closure_ms_since_fault_observation']=round((time.monotonic()-fault_at)*1000)
                    if fault=='temporary':assert record['closure_ms_since_start']<1600,'temporary deadline extended'
                    # A separate backend connection still streams after guard closure.
                    with socket.create_connection(('127.0.0.1',back.server_port),timeout=.3) as source:
                        source.sendall(b'GET /stream HTTP/1.0\r\nHost: fixture\r\n\r\n')
                        wait_for(lambda:b'tick-' in source.recv(4096))
                    record['backend_live_after_guard_closure']=True
                    if fault=='controller-stop':
                        # Supervisors cannot kill their controller. Its stopped PID is not data-plane ownership.
                        os.kill(p.pid,signal.SIGCONT);os.kill(p.pid,signal.SIGTERM)
                    p.wait(timeout=7)
                    wait_for(lambda:all(not pathlib.Path('/proc',str(x)).exists() for x in tracked))
                    assert_dead(tracked,port,ctx)
                    record['owned_absent_before_fallback']=True;record['stream_closed']=True
                    record['elapsed_ms']=round((time.monotonic()-started)*1000)
                    log=(d/'error.log').read_text();(EVIDENCE/(fault+'.error.log')).write_text(log)
                    record['channel_EPERM']=log.count('recvmsg() failed (1: Operation not permitted)')
                    record['internal_errors']=[l for l in log.splitlines() if ('[alert]' in l or '[emerg]' in l) and not (fault=='renew-rebuild' and 'exited on signal 9' in l)]
                    # Runtime/TLS files currently require harness cleanup, not guardian ownership.
                    record['files_before_harness_cleanup']=sorted(x.name for x in d.iterdir())
                    results.append(record);print(json.dumps(record),flush=True)
                finally:
                    if stream:stream.close()
                    for pid in tracked:
                        if pathlib.Path('/proc',str(pid)).exists():
                            try:os.kill(pid,signal.SIGKILL)
                            except ProcessLookupError:pass
                    p.wait(timeout=3)
        finally:back.shutdown();back.server_close();th.join(3)
    assert not pathlib.Path(td).exists(),'fixture TLS cleanup failed'
finally:
    summary={'source_sha256':hashlib.sha256((SRC/'renewable-guard.c').read_bytes()).hexdigest(),
             'nginx_sha256':hashlib.sha256((SDK/'usr/sbin/nginx').read_bytes()).hexdigest(),
             'results':results,'remaining_owned':[p for p in owned if pathlib.Path('/proc',str(p)).exists()]}
    (EVIDENCE/'summary.json').write_text(json.dumps(summary,indent=2)+'\n')
    print('EVIDENCE',EVIDENCE,flush=True)
assert len(results)==9,results
assert all(not r.get('channel_EPERM') and not r.get('internal_errors') for r in results), 'D2b2 RED: real Nginx internal channel recvmsg EPERM; unsafe global relaxation forbidden'
print('PASS guarded Nginx integration including internal channels')
