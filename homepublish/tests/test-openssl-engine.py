#!/usr/bin/env python3
"""Real SDK Nginx actual-open regression; RED is test-only old-env mutant.
No ENGINE registration ABI or host OpenSSL CLI is used for the attack.
"""
import pathlib, subprocess, os, json, hashlib, ctypes, signal, shutil, time, tempfile
EVIDENCE = pathlib.Path(os.environ.get('HP_OPENSSL_ENGINE_EVIDENCE', '/home/eric/homestun-sdk-check/openssl-engine-regression'))
EVIDENCE.mkdir(parents=True, exist_ok=True)
BASE = pathlib.Path(tempfile.mkdtemp(prefix='run-', dir=EVIDENCE))
os.chmod(BASE, 0o700)
SRC = pathlib.Path(__file__).resolve().parents[1] / 'src'
assert os.uname().machine == 'x86_64', 'x86_64 observer only'
assert os.geteuid() != 0, 'run this isolated observer as non-root'
SDK_HOME = pathlib.Path(os.environ.get('HP_TEST_SDK', '/home/eric/homestun-sdk-check/openwrt-sdk-24.10.5-x86-64_gcc-13.3.0_musl.Linux-x86_64'))
SDK = SDK_HOME / 'staging_dir/target-x86_64_musl/root-x86'
F = ['lib/libc.so', 'usr/sbin/nginx', 'usr/lib/libpcre2-8.so.0.11.2', 'usr/lib/libssl.so.3', 'usr/lib/libcrypto.so.3', 'usr/lib/libz.so.1.3.1', 'lib/libgcc_s.so.1']
N = ['loader', 'nginx', 'libpcre2-8.so.0', 'libssl.so.3', 'libcrypto.so.3', 'libz.so.1', 'libgcc_s.so.1']

class Reg(ctypes.Structure):
    _fields_ = [(n, ctypes.c_ulonglong) for n in 'r15 r14 r13 r12 rbp rbx r11 r10 r9 r8 rax rcx rdx rsi rdi orig_rax rip cs eflags rsp ss fs_base gs_base ds es fs gs'.split()]
L = ctypes.CDLL(None, use_errno=True)
L.ptrace.restype = ctypes.c_long
L.ptrace.argtypes = [ctypes.c_uint, ctypes.c_int, ctypes.c_void_p, ctypes.c_void_p]

def ptrace(op, p, addr=None, data=None):
    ctypes.set_errno(0)
    v = L.ptrace(op, p, addr, data)
    if v == -1 and ctypes.get_errno():
        raise OSError(ctypes.get_errno(), 'ptrace')
    return v

def peek(p, a):
    ctypes.set_errno(0)
    v = L.ptrace(2, p, ctypes.c_void_p(a), None)
    if v == -1 and ctypes.get_errno():
        raise OSError(ctypes.get_errno())
    return v & (1 << 64) - 1

def text(p, a):
    b = b''
    for i in range(1024):
        raw = peek(p, a + i * 8).to_bytes(8, 'little')
        b += raw
        if b'\x00' in raw:
            return b.split(b'\x00')[0].decode(errors='replace')
    return b.decode(errors='replace')

def vector(p, a):
    out = []
    for i in range(256):
        q = peek(p, a + i * 8)
        if not q:
            return out
        out.append(text(p, q))
    return out

def wait_owned(p, seconds=20):
    end = time.monotonic() + seconds
    while time.monotonic() < end:
        q, status = os.waitpid(p, os.WNOHANG)
        if q:
            return (q, status)
        time.sleep(0.001)
    raise TimeoutError('owned tracee wait')

def run(argv, **kwargs):
    # Bound every compiler/certificate subprocess, including failure paths.
    return subprocess.run(argv, timeout=30, **kwargs)
cc = str(SDK_HOME / 'staging_dir/toolchain-x86_64_gcc-13.3.0_musl/bin/x86_64-openwrt-linux-musl-gcc')
(B := (BASE / 'module.c')).write_text('#include <fcntl.h>\n#include <unistd.h>\n__attribute__((constructor)) static void loaded(void){int f=open("' + str(BASE / 'UNVERIFIED_DLOPEN') + '",O_CREAT|O_WRONLY,0600);if(f>=0){write(f,"UNVERIFIED_DLOPEN",16);close(f);}}')
try:
    run([cc, '-shared', '-fPIC', str(B), '-o', str(BASE / 'module.so')], check=True, env={**os.environ, 'STAGING_DIR': str(SDK_HOME / 'staging_dir')})
    (BASE / 'injected.cnf').write_text('openssl_conf=init\n[init]\nengines=eng\n[eng]\nprobe=probe\n[probe]\nengine_id=probe\ndynamic_path=' + str(BASE / 'module.so') + '\ninit=1\n')
    run(['openssl', 'req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-keyout', str(BASE / 'key.pem'), '-out', str(BASE / 'cert.pem'), '-days', '1', '-subj', '/CN=probe'], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    results = []
    # RED changes only a copied test fixture's old exec environment.
    # GREEN uses actual current provider sources and their fixed empty config.
    for label in ('red', 'green'):
        d = BASE / label
        d.mkdir(exist_ok=True)
        src = d / 'src'
        src.mkdir(exist_ok=True)
        for original in SRC.iterdir():
            if original.is_file():
                (src / original.name).write_bytes(original.read_bytes())
        if label == 'red':
            provider = src / 'trusted-nginx.c'
            value = provider.read_text()
            fixed = 'char *env[]={"PATH=/usr/bin:/bin","LANG=C",conf,modules,engines,NULL};'
            assert value.count(fixed) == 1
            provider.write_text(value.replace(fixed, 'char *env[]={"PATH=/usr/bin:/bin","LANG=C",NULL};'))
        (d / 'profile.h').write_text('#define HP_TRUST_ROOT ' + json.dumps(str(SDK)) + '\nstatic const struct hp_trust_entry hp_trust_entries[]={' + ','.join(('{' + ','.join((json.dumps(x) for x in (f, n, hashlib.sha256((SDK / f).read_bytes()).hexdigest()))) + '}' for f, n in zip(F, N))) + '};')
        prefix = d / 'owned'
        p=None; paths=[]; execs=[]; status=None; maps=''; bound=False; failure=None
        try:
            prefix.mkdir(mode=0o700, exist_ok=True)
            cfg = 'daemon off; error_log stderr; pid ' + str(prefix / 'runtime/nginx.pid') + '; events {} http { access_log off; client_body_temp_path body; proxy_temp_path proxy; fastcgi_temp_path fastcgi; uwsgi_temp_path uwsgi; scgi_temp_path scgi; server { listen 127.0.0.1:49284 ssl; ssl_certificate ' + str(BASE / 'cert.pem') + '; ssl_certificate_key ' + str(BASE / 'key.pem') + '; } }'
            (d / 'wrap.c').write_text('#include "' + str(src / 'renewable-guard.c') + '"\n#include "trusted-nginx.h"\nextern unsigned char *SHA256(const unsigned char *,size_t,unsigned char *);\nint main(){const char *p=' + json.dumps(str(prefix)) + ';int fd=open(p,O_RDONLY|O_DIRECTORY);struct hp_owned_runtime *r=hp_owned_prepare(fd);if(!r)return 10;unsigned char digest[32];SHA256((const unsigned char *)"",0,digest);setenv("OPENSSL_CONF",' + json.dumps(str(BASE / 'injected.cnf')) + ',1);const char *cfg=' + json.dumps(cfg) + ';if(hp_owned_file(r,2,cfg,strlen(cfg))||worker_boundary(1))return 11;return hp_trusted_nginx_exec(r,p);}')
            run([os.environ.get('HP_OBSERVER_CC','cc'), '-std=c11', '-Werror=implicit-function-declaration', '-DHP_GUARD_TEST', '-DHP_TRUST_PROFILE_HEADER=' + json.dumps(str(d / 'profile.h')), '-I' + str(src), str(d / 'wrap.c'), str(src / 'trusted-nginx.c'), '-l:libcrypto.so.3', '-o', str(d / 'wrapper')], check=True)
            (BASE / 'UNVERIFIED_DLOPEN').unlink(missing_ok=True)
            paths = []
            execs = []
            status = None
            maps = ''
            bound = False
            p = os.fork()
            if not p:
                try:
                    f = os.open(str(d / 'stderr'), os.O_CREAT | os.O_WRONLY | os.O_TRUNC, 0o600)
                    os.dup2(f, 2)
                    ptrace(0, 0, None, None)
                    os.kill(os.getpid(), signal.SIGSTOP)
                    # Warm host manifest hashing under /dev/null; only SDK Nginx sees attack.
                    os.execve(str(d / 'wrapper'), [str(d / 'wrapper')], {'PATH': '/usr/bin:/bin', 'LANG': 'C', 'OPENSSL_CONF': '/dev/null', 'OPENSSL_MODULES': str(BASE), 'OPENSSL_ENGINES': str(BASE)})
                except BaseException:
                    os._exit(125)
            enter = True
            pending = None
            deadline = time.monotonic() + 20
            if os.environ.get('HP_OBSERVER_FAULT') in ('trace-error','trace-timeout'):
                if os.environ['HP_OBSERVER_FAULT']=='trace-timeout':raise TimeoutError('injected trace timeout')
                raise RuntimeError('injected trace exception')
            wait_owned(p)
            ptrace(0x4200, p, None, ctypes.c_void_p(1))
            while True:
                if time.monotonic() > deadline:
                    raise TimeoutError('overall trace deadline')
                ptrace(24, p, None, None)
                _, s = wait_owned(p)
                if os.WIFEXITED(s) or os.WIFSIGNALED(s):
                    status = s
                    break
                if os.WSTOPSIG(s) != 133:
                    continue
                r = Reg()
                ptrace(12, p, None, ctypes.byref(r))
                if enter and r.orig_rax == 59:
                    execs.append({'file': text(p, r.rdi), 'argv': vector(p, r.rsi), 'env': vector(p, r.rdx)})
                # Stop before bind executes: status 9 is observer success, not product failure.
                if enter and r.orig_rax == 49:
                    maps = pathlib.Path('/proc', str(p), 'maps').read_text()
                    bound = True
                    os.kill(p, signal.SIGKILL)
                    _, status = wait_owned(p)
                    break
                if enter and r.orig_rax in (2, 257, 21, 269):
                    path = text(p, r.rsi if r.orig_rax in (257, 269) else r.rdi)
                    pending = {'syscall': r.orig_rax, 'path': path}
                    # Isolated observer redirects only this owned tracee, never system /etc.
                    if path in ('/etc/ssl/openssl.cnf', '/usr/lib/ssl/openssl.cnf'):
                        data = str(BASE / 'injected.cnf').encode() + b'\x00'
                        addr = r.rsp - 2048
                        for k in range(0, len(data), 8):
                            ptrace(5, p, ctypes.c_void_p(addr + k), ctypes.c_void_p(int.from_bytes(data[k:k + 8].ljust(8, b'\x00'), 'little')))
                        if r.orig_rax in (257, 269):
                            r.rsi = addr
                        else:
                            r.rdi = addr
                        ptrace(13, p, None, ctypes.byref(r))
                        pending['observer_redirect'] = str(BASE / 'injected.cnf')
                elif not enter and pending is not None:
                    pending['result'] = ctypes.c_longlong(r.rax).value
                    paths.append(pending)
                    if pending['path'] in (str(BASE / 'module.so'), str(BASE / 'UNVERIFIED_DLOPEN')) and pending['result'] >= 0:
                        try:
                            maps = pathlib.Path('/proc', str(p), 'maps').read_text()
                        except FileNotFoundError:
                            pass
                    pending = None
                enter = not enter
        except BaseException as error:
            failure=type(error).__name__+': '+str(error)
            raise
        finally:
            # Persist observed syscalls, exec env, maps and inode metadata before fallback.
            (d / 'raw.maps').write_text(maps)
            st = []
            for q in sorted((prefix / 'runtime').iterdir()) if (prefix / 'runtime').is_dir() else []:
                z = q.lstat()
                st.append({'name': q.name, 'device': z.st_dev, 'inode': z.st_ino, 'mode': oct(z.st_mode), 'size': z.st_size})
            fixture_metadata=[]
            for q in [prefix, BASE/'key.pem', BASE/'cert.pem']:
                if q.exists():
                    z=q.lstat()
                    fixture_metadata.append({'name':str(q.relative_to(BASE)),'device':z.st_dev,'inode':z.st_ino,'mode':oct(z.st_mode),'links':z.st_nlink})
            (d/'before-fallback.json').write_text(json.dumps({'failure':failure,'pid':p,'runtime':st,'fixture':fixture_metadata,'execs':execs,'file_access':paths,'scope':'single tracee observer; no guardian cleanup'},indent=2))
            try:
                if p is not None:os.kill(p, signal.SIGKILL)
            except ProcessLookupError:
                pass
            cleanup_error = None
            try:
                if p is not None:wait_owned(p, 3)
            except ChildProcessError:
                pass
            except TimeoutError as error:
                cleanup_error = str(error)
            marker = (BASE / 'UNVERIFIED_DLOPEN').exists()
            out = {'case': label, 'failure': failure, 'trace_scope': 'single owned tracee only; stopped before bind; no process-tree claim', 'provider_source_sha256': hashlib.sha256((src / 'trusted-nginx.c').read_bytes()).hexdigest(), 'status': status, 'bind_intercepted_before_listener': bound, 'execs': execs, 'file_access': paths, 'module_marker': marker, 'runtime_metadata_before_observer_cleanup': st, 'cleanup_owner': 'observer probe only; no guardians', 'status_explanation': 'observer SIGKILL at bind entry before any listener, not provider startup failure', 'module_in_maps': str(BASE / 'module.so') in maps, 'pid': p, 'observer_fallback_cleanup': cleanup_error is None, 'cleanup_error': cleanup_error}
            (d / 'observation.json').write_text(json.dumps(out, indent=2))
            results.append(out)
            (d / 'actual-open.json').write_text(json.dumps(paths, indent=2))
            # A stuck tracee is residual/unknown: retain its runtime and evidence.
            assert cleanup_error is None, cleanup_error
            if prefix.exists():shutil.rmtree(prefix)
            assert not prefix.exists()
        print(label, 'marker', marker, 'module_maps', out['module_in_maps'], 'bind', bound, 'paths', len(paths), flush=True)
    assert all((x['bind_intercepted_before_listener'] and x['status'] == 9 for x in results))
    assert results[0]['module_marker'] and results[0]['module_in_maps']
    assert not results[1]['module_marker'] and (not results[1]['module_in_maps'])
    assert any((x['path'] in ('/etc/ssl/openssl.cnf', '/usr/lib/ssl/openssl.cnf') and x['result'] >= 0 for x in results[0]['file_access']))
    assert any((x['path'] == str(BASE / 'module.so') and x['result'] >= 0 for x in results[0]['file_access']))
    assert any((x['path'] == str(BASE / 'UNVERIFIED_DLOPEN') and x['result'] >= 0 for x in results[0]['file_access']))
    assert not any((x['path'] in ('/etc/ssl/openssl.cnf', '/usr/lib/ssl/openssl.cnf', str(BASE / 'injected.cnf'), str(BASE / 'module.so'), str(BASE / 'UNVERIFIED_DLOPEN')) for x in results[1]['file_access']))
    assert any((x['path'].endswith('/runtime/openssl.cnf') and x['result'] >= 0 for x in results[1]['file_access']))
    assert results[1]['execs'][-1]['env'] == ['PATH=/usr/bin:/bin', 'LANG=C', 'OPENSSL_CONF=' + str(BASE / 'green/owned/runtime/openssl.cnf'), 'OPENSSL_MODULES=' + str(BASE / 'green/owned/runtime'), 'OPENSSL_ENGINES=' + str(BASE / 'green/owned/runtime')]
    (BASE / 'attack-summary.json').write_text(json.dumps({'passed': True, 'cases': [{'case': x['case'], 'module_marker': x['module_marker'], 'module_in_maps': x['module_in_maps'], 'bind_intercepted_before_listener': x['bind_intercepted_before_listener']} for x in results]}, indent=2))
    print('PASS real Nginx actual-open SDK constructor RED -> GREEN; evidence ' + str(BASE), flush=True)
finally:
    (BASE / 'key.pem').unlink(missing_ok=True)
    (BASE / 'cert.pem').unlink(missing_ok=True)
