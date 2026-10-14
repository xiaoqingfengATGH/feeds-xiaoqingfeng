#!/usr/bin/env python3
"""D2b3 real fixed-provider private-pair acceptance gate.
Cached fixed Nginx; no installs, production helpers, DNS, firewall or activation.
Channel errors remain hard failures; no production activation is provided.
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
assert 'OPENSSL_CONF=' in (SRC/'trusted-nginx.c').read_text()
assert 'openssl.cnf' in (SRC/'owned-runtime.inc').read_text()
results=[]
def cleanup_snapshot(d, tracked, p):
    runtime=d/'runtime'
    entries=[]
    if runtime.exists():
        for q in sorted(runtime.rglob('*')):
            s=q.lstat()
            entries.append({'name':str(q.relative_to(runtime)), 'inode':s.st_ino,
                            'device':s.st_dev, 'mode':oct(s.st_mode), 'links':s.st_nlink})
    return {'runtime_exists':runtime.exists(), 'entries':entries,
            'controller_returncode':p.poll(),
            'owned_pid_states':{str(pid):pathlib.Path('/proc',str(pid),'status').read_text().split('State:')[1].splitlines()[0].strip()
                                for pid in tracked if pathlib.Path('/proc',str(pid),'status').exists()}}
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
def elf_map_set(pid,runtime):
    """Return only file-backed ELF candidates, not a substring exclusion."""
    out=set()
    for line in pathlib.Path('/proc',str(pid),'maps').read_text().splitlines():
        fields=line.split(None,5)
        if len(fields)<6: continue
        path=fields[5].strip()
        if path.startswith('/memfd:') or path.startswith(str(runtime)+'/'):
            out.add(path)
    return out
def compile_fixture(d):
    files=["lib/libc.so","usr/sbin/nginx","usr/lib/libpcre2-8.so.0.11.2","usr/lib/libssl.so.3","usr/lib/libcrypto.so.3","usr/lib/libz.so.1.3.1","lib/libgcc_s.so.1"]
    names=["loader","nginx","libpcre2-8.so.0","libssl.so.3","libcrypto.so.3","libz.so.1","libgcc_s.so.1"]
    header=d/"trusted-profile.h"
    rows=["{"+json.dumps(f)+","+json.dumps(n)+","+json.dumps(hashlib.sha256((SDK/f).read_bytes()).hexdigest())+"}" for f,n in zip(files,names)]
    header.write_text("#define HP_TRUST_ROOT "+json.dumps(str(SDK))+"\nstatic const struct hp_trust_entry hp_trust_entries[]={"+",".join(rows)+"};\n")
    vals={'HP_NGINX_LOADER':SDK/'lib/ld-musl-x86_64.so.1',
          'HP_NGINX_EXEC':SDK/'usr/sbin/nginx',
          'HP_NGINX_LIBS':str(SDK/'lib')+':'+str(SDK/'usr/lib'),
          'HP_NGINX_PREFIX':d,'HP_FOREIGN_SOCKET':d/'foreign.sock'}
    subprocess.run(['cc','-std=c11','-Wall','-Wextra','-Werror','-DHP_GUARD_TEST','-I'+str(SRC),
                    *['-D'+k+'='+json.dumps(str(v)) for k,v in vals.items()],
                    '-DHP_TRUST_PROFILE_HEADER='+json.dumps(str(header)),str(SRC/'trusted-nginx.c'),
                    str(SRC/'renewable-guard.c'),str(ROOT/'homepublish/tests/guardian-nginx-fixture.c'),
                    '-o',str(d/'fixture'),'-l:libcrypto.so.3'],check=True)
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
def foreign_test(d,exe,abstract=False):
    listener=socket.socket(socket.AF_UNIX,socket.SOCK_STREAM);listener.bind(('\0' if abstract else '')+str(d/'foreign.sock'));listener.listen()
    sentinel=d/'foreign.txt';sentinel.write_text('foreign-preserved')
    errors=[];sent=[]
    def sender():
        try:
            listener.settimeout(3)
            with listener.accept()[0] as s, sentinel.open('rb') as f:
                sent.append(s.sendmsg([b'F'],[(socket.SOL_SOCKET,socket.SCM_RIGHTS,array.array('i',[f.fileno()]))]))
        except Exception as e:errors.append(repr(e))
    th=threading.Thread(target=sender);th.start()
    p=subprocess.run([str(exe),'foreign-abstract' if abstract else 'foreign','0'],capture_output=True,text=True,timeout=6)
    th.join(4)
    assert not th.is_alive() and not errors,(errors,p.stdout,p.stderr)
    assert p.returncode==0 and 'recvmsg rc=-1 errno=1' in p.stdout,(p.returncode,p.stdout,p.stderr)
    assert sent==[1] and sentinel.read_text()=='foreign-preserved',sent
    guardian=int(p.stdout.split('guardian=')[1].splitlines()[0]);assert not pathlib.Path('/proc',str(guardian)).exists()
    print('PASS real external pathname UNIX SCM_RIGHTS queued; guarded recvmsg EPERM',flush=True)
    results.append({'case':'foreign-SCM_RIGHTS-'+('abstract' if abstract else 'pathname'),'queued_bytes':sent,'recvmsg_errno':1,'guardian_absent':True})
    # Same live foreign endpoint exists; private profile cannot create a UNIX
    # connector at all. recvmsg is genuinely enabled, not silently still denied.
    p=subprocess.run([str(exe),'private-foreign','0'],capture_output=True,text=True,timeout=6)
    assert p.returncode==0 and 'socket errno=1 recvmsg errno=9' in p.stdout,(p.stdout,p.stderr)
    assert sentinel.read_text()=='foreign-preserved'
    listener.close()
    results.append({'case':'private-foreign-'+('abstract' if abstract else 'pathname'),'socket_errno':1,'recvmsg_invalid_errno':9,'foreign_preserved':True})
try:
    with tempfile.TemporaryDirectory(prefix='d2b2-nginx-',dir=os.environ.get('TMPDIR','/home/eric/homestun-sdk-check')) as td:
        base=pathlib.Path(td);ctx=certify(base)
        back=Server(('127.0.0.1',0),Backend);th=threading.Thread(target=back.serve_forever);th.start()
        try:
            probe=base/'probe';probe.mkdir();exe=compile_fixture(probe);foreign_test(probe,exe);foreign_test(probe,exe,True)
            for fault in ('renew-rebuild','temporary','controller-kill','controller-stop','guardian-kill','guardian-stop','watchdog-kill','watchdog-stop'):
                d=base/fault;d.mkdir(mode=0o700)
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
                config=config.replace(str(d/'cert.pem'),str(d/'runtime/cert.pem')).replace(str(d/'key.pem'),str(d/'runtime/key.pem'))
                config=config.replace(str(d/'nginx.pid'),str(d/'runtime/nginx.pid'))
                # No disk buffering/temp creation in this flat lifecycle slice.
                config=config.replace('proxy_next_upstream off;', 'proxy_next_upstream off; proxy_buffering off;')
                sentinel=d/'foreign.txt';sentinel.write_text('foreign-preserved');identity=sentinel.stat()
                originals={n:hashlib.sha256((d/n).read_bytes()).hexdigest() for n in ('cert.pem','key.pem')}
                (d/'nginx.conf').write_text(config)
                exe=compile_fixture(d)
                started=time.monotonic();p=subprocess.Popen([str(exe),'nginx','1200' if fault=='temporary' else '0'],stdout=subprocess.PIPE,text=True,env={**os.environ,'HP_OWNED_RUNTIME':'1','HP_TEST_INJECT_ENV':'1','HP_CLIENT_MANIFEST':'/not-trusted'})
                owned.add(p.pid);tracked={p.pid};stream=None
                try:
                    line=p.stdout.readline().strip();assert 'rc=0' in line,line
                    guardian=int(line.split('guardian=')[1]);tracked.add(guardian)
                    wait_for(lambda:b'guarded-backend' in request('127.0.0.1',port,ctx))
                    assert b'guarded-backend' in request('::1',port,ctx)
                    watchdog=children(guardian)[0];master=children(watchdog)[0];tracked.update([watchdog,master])
                    workers=wait_for(lambda:children(master) if len(children(master))==2 else None);tracked.update(workers);owned.update(tracked)
                    assert (d/'runtime').stat().st_mode & 0o777 == 0o700
                    for n in ('cert.pem','key.pem','nginx.conf','nginx.pid'):
                        assert (d/'runtime'/n).stat().st_mode & 0o777 == 0o600
                    stream=connect('127.0.0.1',port,ctx);stream.sendall(b'GET /stream HTTP/1.0\r\nHost: service.home\r\n\r\n')
                    wait_for(lambda:b'tick-' in stream.recv(4096))
                    record={'case':fault,'master':master,'workers':workers,'port':port,'TLS_v4_v6':True}
                    environ=pathlib.Path('/proc',str(master),'environ').read_bytes().split(b'\0')
                    # Nginx rewrites argv/environ for its process title; forbidden markers
                    # must not survive, but PATH visibility is not promised.
                    assert not any(b'/not-trusted' in x or x.startswith((b'LD_',b'HP_')) for x in environ),environ
                    trace=(d/'runtime/provider-init.trace').read_text()
                    assert 'OPENSSL_CONF='+str(d/'runtime/openssl.cnf') in trace,trace
                    assert 'OPENSSL_MODULES='+str(d/'runtime') in trace,trace
                    assert '/not-trusted' not in trace and 'OPENSSL_ENGINES='+str(d/'runtime') in trace,trace
                    record['fixed_execve_environment_evidence']=trace
                    expected={str(d/'runtime'/name) for name in ('libpcre2-8.so.0','libssl.so.3','libcrypto.so.3','libz.so.1','libgcc_s.so.1')}
                    expected.add('/memfd:hp-loader (deleted)')
                    expected.add('/memfd:hp-nginx (deleted)')
                    map_records={str(pid):sorted(elf_map_set(pid,d/'runtime')) for pid in (master,*workers)}
                    assert all(set(values)==expected for values in map_records.values()),map_records
                    assert all(str(SDK) not in values for values in map_records.values()),map_records
                    record['verified_actual_dependency_maps']=map_records;record['environment_injection_removed']=True
                    record['fd_roles']={str(pid):{q.name:os.readlink(q) for q in pathlib.Path('/proc',str(pid),'fd').iterdir()} for pid in (guardian,watchdog,master,*workers)}
                    record['worker_boundary']={str(pid):{line.split(':')[0]:line.split(':',1)[1].strip() for line in pathlib.Path('/proc',str(pid),'status').read_text().splitlines() if line.startswith(('Uid:','Gid:','NoNewPrivs:','Seccomp:'))} for pid in (master,*workers)}
                    assert all(v['NoNewPrivs']=='1' and v['Seccomp']=='2' for v in record['worker_boundary'].values())
                    if fault=='renew-rebuild':
                        os.kill(workers[0],signal.SIGKILL)
                        new=wait_for(lambda:children(master) if len(children(master))==2 and workers[0] not in children(master) else None)
                        tracked.update(new);owned.update(new);record['rebuilt_workers']=new
                        rebuilt_maps={str(pid):sorted(elf_map_set(pid,d/'runtime')) for pid in new}
                        assert all(set(values)==expected for values in rebuilt_maps.values()),rebuilt_maps
                        record['respawn_worker_dependency_maps']=rebuilt_maps
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
                    # Observe native-owned runtime before fallback; source fixture copies are separate.
                    assert not (d/'runtime').exists(), 'D2c1 RED: native-owned TLS/config/pid remain before harness cleanup'
                    record['native_owned_runtime_absent']=True
                    assert sentinel.read_text()=='foreign-preserved' and sentinel.stat().st_ino==identity.st_ino
                    assert all(hashlib.sha256((d/n).read_bytes()).hexdigest()==h for n,h in originals.items())
                    record['foreign_inode_and_source_TLS_preserved']=True
                    record['files_before_harness_cleanup']=sorted(x.name for x in d.iterdir())
                    results.append(record);print(json.dumps(record),flush=True)
                finally:
                    # Persist metadata before any fallback kill or TemporaryDirectory removal,
                    # including failed assertions; never record secret file contents.
                    (EVIDENCE/(fault+'.cleanup.json')).write_text(json.dumps(cleanup_snapshot(d,tracked,p),indent=2)+'\n')
                    if (d/'stderr').exists():(EVIDENCE/(fault+'.stderr')).write_bytes((d/'stderr').read_bytes())
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
assert len(results)==12,results
assert all(not r.get('channel_EPERM') and not r.get('internal_errors') for r in results), 'D2b2 RED: real Nginx internal channel recvmsg EPERM; unsafe global relaxation forbidden'
print('PASS guarded Nginx integration including internal channels')
