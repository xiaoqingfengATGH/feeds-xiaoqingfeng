#!/usr/bin/env python3
"""Real HomeVPN resolver, metadata, provider snapshots/SNI/readiness; local adapter, not procd."""
import pathlib, tempfile, subprocess, os, shutil, threading, http.server, socket, ssl, time, hashlib
ROOT=pathlib.Path(__file__).resolve().parents[2]
SHARE=ROOT/'homepublish/files/usr/share/homepublish'
LUA='/home/eric/homestun-sdk-check/local-tools/usr/bin/lua5.1'
SDK=pathlib.Path('/home/eric/homestun-sdk-check/openwrt-sdk-24.10.5-x86-64_gcc-13.3.0_musl.Linux-x86_64/staging_dir/target-x86_64_musl/root-x86')
NGINX=f'{SDK}/lib/ld-musl-x86_64.so.1 --library-path {SDK}/lib:{SDK}/usr/lib {SDK}/usr/sbin/nginx'
def run(*args,**kw):
 p=subprocess.run(args,text=True,capture_output=True,**kw)
 assert p.returncode==0,(p.stdout,p.stderr)
 return p
class Handler(http.server.BaseHTTPRequestHandler):
 def do_GET(self):self.send_response(200);self.end_headers();self.wfile.write(self.headers['Host'].encode())
 def log_message(self,*a):pass
with tempfile.TemporaryDirectory(prefix='hp-shared-',dir='/home/eric/homestun-sdk-check') as td:
 d=pathlib.Path(td);d.chmod(0o755);modules=d/'modules';shutil.copytree(SHARE,modules)
 state=d/'acme';sources=[]
 for kind,keyargs in [('rsa',['-newkey','rsa:2048']),('ecc',['-newkey','ec','-pkeyopt','ec_paramgen_curve:P-256'])]:
  p=state/('*.fixture.home'+('_ecc' if kind=='ecc' else ''));p.mkdir(parents=True)
  cert=p/'fullchain.cer';key=p/'*.fixture.home.key'
  run('openssl','req','-x509',*keyargs,'-nodes','-keyout',str(key),'-out',str(cert),'-days','1','-subj','/CN=wrong.invalid','-addext','subjectAltName=DNS:*.fixture.home,DNS:fixture.home')
  sources.extend([cert,key])
 hashes={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}
 resolver=d/'acme-resolve.sh';resolver.write_text((ROOT/'luci-app-homevpn/root/usr/share/homevpn/acme-resolve.sh').read_text())
 integration=modules/'device-integrations.lua';integration.write_text(integration.read_text().replace('/usr/share/homevpn/acme-resolve.sh',str(resolver)))
 provider=modules/'product-device-provider.lua';provider.write_text(provider.read_text().replace('/tmp/homepublish-device/runtime',str(d/'runtime')).replace('/usr/sbin/nginx',NGINX))
 server=http.server.ThreadingHTTPServer(('127.0.0.1',49285),Handler);thread=threading.Thread(target=server.serve_forever);thread.start()
 try:
  for independent in [False,True]:
   script=d/'test.lua';script.write_text("""
package.path=arg[1]..'/?.lua;'..package.path
package.preload.uci=function()return {cursor=function()return {foreach=function(self,a,b,fn)for _,v in ipairs({{['.name']='fixture_rsa',domains={'*.fixture.home'},key_type='rsa2048'},{['.name']='fixture_ecc',domains={'*.fixture.home'},key_type='ec256'}})do fn(v)end end}end}end
local I=require('device-integrations');assert(I.certificate_source('acme:fixture_rsa','a.fixture.home'));assert(not I.certificate_source('acme:fixture_rsa','deep.a.fixture.home'))
local execute=os.execute;os.execute=function(cmd)
 if cmd=='test -f /etc/homepublish/device-test/enabled' then return 0 end
 if cmd=='/etc/init.d/homepublish-nginx start' then return execute('"""+NGINX+' -p '+str(d/'runtime')+"""/ -c nginx.conf >"""+str(d/'nginx.log')+""" 2>&1 &') end
 return execute(cmd)
end
local P=require('product-device-provider')
local function s(id,host,ref)return {service_id=id,hostname=host,certificate_ref=ref,backend={addressFamily='ipv4',host='127.0.0.1',port=49285,allowed_ranges={'127.0.0.0/8'}},authentication_review={authentication='confirmed',management=false}}end
local c={services={s('fixture','a.fixture.home','acme:fixture_rsa'),s('fixture2','b.fixture.home','"""+('acme:fixture_ecc' if independent else 'acme:fixture_rsa')+"""')},access_profile={methods_allowed={'manual_ipv4'},listeners={{protocol='tcp',family='ipv4',address='192.168.1.2',interface='br-lan',zone='lan',internal_port=49284,external_port=49284}}}}
local plan,e=P.plan(c);assert(plan,e);assert(P.start(plan,1,0));local ok,rows=P.readiness();assert(ok and rows.fixture.ready and rows.fixture2.ready,'all-service actual TLS readiness')
print('PASS actual resolver inventory identity differs from service hostname; snapshot/start/readiness')
""")
   try:
    result=run(LUA,str(script),str(modules),env={**os.environ,'HV_ACME_STATE_DIR':str(state),'HV_ACME_LINK_DIR':str(d/'absent')});print(result.stdout)
    for host,kind in [('a.fixture.home','rsa'),('b.fixture.home','ecc' if independent else 'rsa')]:
     cert=sources[2 if kind=='ecc' else 0];ctx=ssl.create_default_context(cafile=str(cert))
     with ctx.wrap_socket(socket.create_connection(('127.0.0.1',49284)),server_hostname=host) as conn:
      conn.sendall(f'GET / HTTP/1.0\r\nHost: {host}\r\n\r\n'.encode());body=b''
      while chunk:=conn.recv(4096):body+=chunk
      assert host.encode() in body,body
    try:
     with ssl.create_default_context(cafile=str(sources[0])).wrap_socket(socket.create_connection(('127.0.0.1',49284)),server_hostname='unknown.fixture.home'):pass
    except ssl.SSLError:pass
    else:raise AssertionError('unknown SNI accepted')
    print('PASS '+('independent RSA/ECC' if independent else 'shared wildcard multiSAN')+' actual TLS backend mapping and unknown SNI refusal')
   finally:
    pidfile=d/'runtime/nginx.pid'
    if pidfile.exists():
     pid=int(pidfile.read_text());os.kill(pid,15)
     for _ in range(100):
      try:socket.create_connection(('127.0.0.1',49284),timeout=.1).close()
      except OSError:break
      time.sleep(.05)
     else:raise AssertionError('listener remains')
    if (d/'nginx.log').exists():print((d/'nginx.log').read_text())
    shutil.rmtree(d/'runtime',ignore_errors=True)
  assert hashes=={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}
 finally:server.shutdown();server.server_close();thread.join()
print('PASS source hashes preserved; private runtime/listeners and fixture removed')
