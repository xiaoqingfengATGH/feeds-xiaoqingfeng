#!/usr/bin/env python3
"""Local-only regression; SDK nginx, no router or UPnP operations."""
import argparse, importlib.util, json, os, pathlib, signal, socket, ssl, subprocess, tempfile, threading, time

HOST = 'homestun-test.homelede.com'

def probe(address, port, *, cafile=None, seconds=16):
    start = time.monotonic()
    result = {'headers': None, 'ticks': [], 'bytes': 0}
    with socket.create_connection((address, port), 3) as raw:
        context = ssl.create_default_context(cafile=str(cafile)) if cafile else None
        sock = context.wrap_socket(raw, server_hostname=HOST) if context else raw
        with sock:
            sock.settimeout(3)
            sock.sendall(f'GET /hold HTTP/1.1\r\nHost: {HOST}\r\nConnection: close\r\n\r\n'.encode())
            buf = b''
            try:
                while time.monotonic() - start < seconds:
                    data = sock.recv(4096)
                    if not data:
                        result['outcome'] = 'EOF'
                        break
                    result['bytes'] += len(data)
                    buf += data
                    if result['headers'] is None and b'\r\n\r\n' in buf:
                        header, buf = buf.split(b'\r\n\r\n', 1)
                        result['headers'] = header.decode('ascii')
                        result['headers_elapsed'] = time.monotonic() - start
                    # Raw chunk framing is kept; complete numbered application lines only.
                    while b'\n' in buf and result['headers'] is not None:
                        line, buf = buf.split(b'\n', 1)
                        if line.startswith(b'tick '):
                            parts = line.decode('ascii').strip().split()
                            result['ticks'].append({'number': int(parts[1]), 'source_monotonic': float(parts[2]), 'received_elapsed': time.monotonic()-start})
            except socket.timeout:
                result['outcome'] = 'socket_timeout'
    result['elapsed'] = time.monotonic()-start
    return result

def validate(r):
    assert r['headers'] and '200 OK' in r['headers'], 'No HTTP response headers (zero-byte hold)'
    assert len(r['ticks']) >= 6, f"Not enough application ticks: {len(r['ticks'])}"
    ticks = r['ticks']
    assert [t['number'] for t in ticks] == list(range(1, len(ticks)+1)), 'Missing/reordered ticks'
    gaps = [b['received_elapsed']-a['received_elapsed'] for a,b in zip(ticks,ticks[1:])]
    assert all(1.5 < g < 2.5 for g in gaps), f'Buffered/nonperiodic traffic: {gaps}'
    assert ticks[-1]['received_elapsed']-ticks[0]['received_elapsed'] >= 10, 'Span below 10s'
    assert all(b['source_monotonic'] > a['source_monotonic'] for a,b in zip(ticks,ticks[1:])), 'Nonmonotonic source'
    assert r['elapsed'] >= 16, 'Source ended before bounded observation window; cannot reuse for cutoff'
    assert r['headers_elapsed'] < 1, 'Headers delayed'

def free_port():
    with socket.socket() as s:
        s.bind(('127.0.0.1',0))
        return s.getsockname()[1]

def main():
    p = argparse.ArgumentParser()
    p.add_argument('--legacy', action='store_true')
    p.add_argument('--sdk-root', required=True)
    p.add_argument('--loader', required=True)
    p.add_argument('--scratch', required=True)
    p.add_argument('--output', required=True)
    args=p.parse_args()
    root=pathlib.Path(args.sdk_root)
    cmd=[args.loader,'--library-path',f'{root}/lib:{root}/usr/lib',str(root/'usr/sbin/nginx')]
    ports=[free_port() for _ in range(3)]
    assert len(set(ports))==3
    backend, plain, tls=ports
    result={'mode':'legacy' if args.legacy else 'corrected', 'scope':'WSL loopback only; no UPnP', 'ports':ports}
    proc=None; server=None; worker=None
    directory=tempfile.mkdtemp(prefix='homestun-stream-',dir=args.scratch)
    d=pathlib.Path(directory)
    try:
        subprocess.run(['openssl','req','-x509','-newkey','rsa:2048','-nodes','-keyout',str(d/'key.pem'),'-out',str(d/'cert.pem'),'-subj',f'/CN={HOST}','-addext',f'subjectAltName=DNS:{HOST}','-days','1'],check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,timeout=10)
        os.chmod(d/'key.pem',0o600)
        if args.legacy:
            source=f"server {{ listen 127.0.0.1:{backend}; server_name {HOST}; location /hold {{ limit_rate 1; return 200 '"+('fixture-marker'*12)+"'; } }"
        else:
            spec=importlib.util.spec_from_file_location('fixture',pathlib.Path(__file__).with_name('homestun-upnp-stream-fixture.py'))
            module=importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
            server=module.make_server(backend)
            worker=threading.Thread(target=server.serve_forever,daemon=True); worker.start()
            source=''
        location=f'location / {{ proxy_pass http://127.0.0.1:{backend}; proxy_http_version 1.1; proxy_set_header Host {HOST}; proxy_buffering off; }}'
        config=f'''worker_processes 1; pid {d}/nginx.pid; error_log {d}/error.log; daemon off;
 events {{ worker_connections 32; }} http {{ access_log off; client_body_temp_path {d}/body; proxy_temp_path {d}/proxy; fastcgi_temp_path {d}/fastcgi; uwsgi_temp_path {d}/uwsgi; scgi_temp_path {d}/scgi; proxy_read_timeout 240s; proxy_send_timeout 240s; send_timeout 240s;
 {source}
 server {{ listen 127.0.0.1:{plain}; server_name {HOST}; {location} }}
 server {{ listen 127.0.0.1:{tls} ssl default_server; server_name _; ssl_certificate {d}/cert.pem; ssl_certificate_key {d}/key.pem; return 444; }}
 server {{ listen 127.0.0.1:{tls} ssl; server_name {HOST}; ssl_certificate {d}/cert.pem; ssl_certificate_key {d}/key.pem; {location} }} }}'''
        (d/'nginx.conf').write_text(config)
        subprocess.run(cmd+['-t','-p',directory+'/', '-c',str(d/'nginx.conf')],check=True,capture_output=True,timeout=5)
        result['nginx_version']=subprocess.run(cmd+['-v'],capture_output=True,text=True,check=True).stderr.strip()
        proc=subprocess.Popen(cmd+['-p',directory+'/', '-c',str(d/'nginx.conf')],start_new_session=True,stdout=subprocess.DEVNULL,stderr=subprocess.PIPE)
        deadline=time.monotonic()+3
        while True:
            try:
                with socket.create_connection(('127.0.0.1',tls),0.2): break
            except OSError:
                if time.monotonic()>deadline: raise RuntimeError('nginx not listening')
                time.sleep(0.05)
        for label,port,ca in [('raw_http',plain,None),('verified_tls',tls,d/'cert.pem')]:
            result[label]=probe('127.0.0.1',port,cafile=ca)
            validate(result[label])
        result['status']='PASS'
    except Exception as ex:
        result['status']='FAIL'; result['error']=str(ex)
        if (d/'error.log').exists(): result['nginx_error']=(d/'error.log').read_text()
    finally:
        if proc:
            os.killpg(proc.pid,signal.SIGTERM)
            try: proc.wait(timeout=4)
            except subprocess.TimeoutExpired:
                os.killpg(proc.pid,signal.SIGKILL); proc.wait(timeout=2)
        if server:
            server.shutdown(); server.server_close(); worker.join(timeout=2)
        result['cleanup']={'process_exited':proc is None or proc.poll() is not None}
        for port in ports:
            with socket.socket() as s:
                result['cleanup'][str(port)+'_closed']=s.connect_ex(('127.0.0.1',port))!=0
        import shutil
        shutil.rmtree(d)
        result['cleanup']['fixture_directory_removed']=not d.exists()
        pathlib.Path(args.output).write_text(json.dumps(result,indent=2)+'\n')
        print(json.dumps(result,indent=2))
    return 0 if result['status']=='PASS' and all(result['cleanup'].values()) else 1

if __name__=='__main__':
    raise SystemExit(main())
