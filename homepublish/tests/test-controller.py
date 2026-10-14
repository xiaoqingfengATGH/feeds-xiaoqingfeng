#!/usr/bin/env python3
"""Bounded internal controller host scope; real journal/renderer/guarded TLS."""
import hashlib, http.server, importlib.util, json, os, pathlib, select, socket, ssl, subprocess, tempfile, threading, time
ROOT=pathlib.Path(__file__).resolve().parents[2]
SHARE=ROOT/'homepublish/files/usr/share/homepublish'
SRC=ROOT/'homepublish/src'
LUA='/home/eric/homestun-sdk-check/local-tools/usr/bin/lua5.1'
DEV='/home/eric/homestun-sdk-check/canonical-lua-dev/usr/include'
SDK=pathlib.Path('/home/eric/homestun-sdk-check/openwrt-sdk-24.10.5-x86-64_gcc-13.3.0_musl.Linux-x86_64/staging_dir/target-x86_64_musl/root-x86')
def wire(v):
 if isinstance(v,bool):return 'b1' if v else 'b0'
 if isinstance(v,int):return f'i{v};'
 if isinstance(v,str):return f's{len(v.encode())}:{v}'
 if isinstance(v,list):v=dict(enumerate(v,1))
 if isinstance(v,dict):return f't{len(v)}:'+''.join(wire(k)+wire(x) for k,x in v.items())
 raise TypeError(v)
def decode(s):
 s=s.strip();assert s.startswith('HP1');i=3
 def get():
  nonlocal i
  c=s[i];i+=1
  if c=='b':v=s[i]=='1';i+=1;return v
  end=s.index(';' if c=='i' else ':',i);n=int(s[i:end]);i=end+1
  if c=='i':return n
  if c=='s':v=s[i:i+n];i+=n;return v
  assert c=='t';v={}
  for _ in range(n):k=get();v[k]=get()
  return v
 v=get();assert i==len(s);return v
class Backend(http.server.BaseHTTPRequestHandler):
 def log_message(self,*a):pass
 def do_GET(self):self.send_response(200);self.end_headers();self.wfile.write(b'controller-real-backend')
def compile_adapter(d):
 files=['lib/libc.so','usr/sbin/nginx','usr/lib/libpcre2-8.so.0.11.2','usr/lib/libssl.so.3','usr/lib/libcrypto.so.3','usr/lib/libz.so.1.3.1','lib/libgcc_s.so.1']
 names=['loader','nginx','libpcre2-8.so.0','libssl.so.3','libcrypto.so.3','libz.so.1','libgcc_s.so.1']
 header=d/'trusted-profile.h'
 rows=['{'+json.dumps(f)+','+json.dumps(n)+','+json.dumps(hashlib.sha256((SDK/f).read_bytes()).hexdigest())+'}' for f,n in zip(files,names)]
 header.write_text('#define HP_TRUST_ROOT '+json.dumps(str(SDK))+'\nstatic const struct hp_trust_entry hp_trust_entries[]={'+','.join(rows)+'};\n')
 vals={'HP_NGINX_LOADER':SDK/'lib/ld-musl-x86_64.so.1','HP_NGINX_EXEC':SDK/'usr/sbin/nginx','HP_NGINX_LIBS':str(SDK/'lib')+':'+str(SDK/'usr/lib'),'HP_NGINX_PREFIX':d,'HP_FOREIGN_SOCKET':d/'foreign.sock'}
 subprocess.run(['cc','-std=c11','-Wall','-Wextra','-Werror','-fPIC','-shared','-DHP_GUARD_TEST','-I'+str(SRC),'-I'+DEV+'/lua5.1','-I'+DEV+'/x86_64-linux-gnu',*['-D'+k+'='+json.dumps(str(v)) for k,v in vals.items()],'-DHP_TRUST_PROFILE_HEADER='+json.dumps(str(header)),str(SRC/'trusted-nginx.c'),str(SRC/'renewable-guard.c'),str(ROOT/'homepublish/tests/controller-adapter.c'),'-o',str(d/'homepublish_controller_test.so'),'-l:libcrypto.so.3'],check=True)
def main():
 assert (SHARE/'product-controller.lua').exists(),'internal runnable controller missing'
 with tempfile.TemporaryDirectory(prefix='controller-',dir='/home/eric/homestun-sdk-check') as td:
  d=pathlib.Path(td);env={**os.environ,'LUA_CPATH':str(d/'?.so')}
  subprocess.run(['cc','-std=c99','-Wall','-Wextra','-Werror','-Wno-misleading-indentation','-fPIC','-shared','-I'+DEV+'/lua5.1','-I'+DEV+'/x86_64-linux-gnu','-DPRODUCT_ROOT='+json.dumps(str(d/'store')),str(SRC/'product-store.c'),'-o',str(d/'homepublish_store.so')],check=True)
  def cli(req,ok=True):
   p=subprocess.run([LUA,str(SHARE/'product-cli.lua')],input='HP1'+wire(req),text=True,capture_output=True,env=env,timeout=3)
   assert (p.returncode==0)==ok,(p.stdout,p.stderr)
   return decode(p.stdout) if ok else p.stderr
  backend=http.server.ThreadingHTTPServer(('127.0.0.1',0),Backend);thread=threading.Thread(target=backend.serve_forever);thread.start();p=None
  with socket.socket() as s:s.bind(('127.0.0.1',0));port=s.getsockname()[1]
  config={'schema_version':1,'services':[{'service_id':'fixture','name':'original','hostname':'service.home','backend':{'host':'127.0.0.1','port':backend.server_port,'allowed_ranges':['127.0.0.0/8']},'certificate_ref':'import:fixture','authentication_review':{'authentication':'confirmed','management':False}}],'access_profile':{'methods_allowed':['manual_ipv4'],'listeners':[{'family':'ipv4','address':'192.168.1.2','interface':'fixture','zone':'fixture','protocol':'tcp','internal_port':port,'external_port':port}]}}
  def absent():
   try:socket.create_connection(('127.0.0.1',port),timeout=.1).close()
   except OSError:return True
   return False
  try:
   state=cli({'action':'save','expected_revision':0,'config':config});assert state['saved_revision']==1 and 'active_revision' not in state and absent()
   assert 'unsupported' in cli({'action':'start'},False)
   def run(*args):subprocess.run(args,check=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
   run('openssl','req','-x509','-newkey','rsa:2048','-nodes','-keyout',str(d/'key.pem'),'-out',str(d/'cert.pem'),'-days','1','-subj','/CN=service.home','-addext','subjectAltName=DNS:service.home')
   compile_adapter(d)
   p=subprocess.Popen([LUA,str(ROOT/'homepublish/tests/controller-host.lua'),str(SHARE),str(d),str(port),str(backend.server_port)],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,env=env)
   def call(req):
    p.stdin.write('HP1'+wire(req)+'\n');p.stdin.flush();assert select.select([p.stdout],[],[],4)[0],'controller response timeout'
    line=p.stdout.readline();assert line,(p.poll(),p.stderr.read());return decode(line)
   rejected=call({'action':'start','revision':1,'approved':False});assert rejected['error']=='approval required' and absent()
   started=call({'action':'start','revision':1,'approved':True});assert started['runtime']['phase']=='running',started
   generation=started['runtime']['generation']
   ctx=ssl.create_default_context(cafile=str(d/'cert.pem'))
   def tls():
    with ctx.wrap_socket(socket.create_connection(('127.0.0.1',port),timeout=.4),server_hostname='service.home') as s:
     s.sendall(b'GET / HTTP/1.0\r\nHost: service.home\r\n\r\n');data=b''
     while True:
      v=s.recv(4096)
      if not v:break
      data+=v
     assert b'controller-real-backend' in data,data
   deadline=time.monotonic()+3
   while True:
    try:tls();break
    except (ConnectionRefusedError,ssl.SSLError):
     if time.monotonic()>=deadline:raise
     time.sleep(.02)
   time.sleep(1.4);tls() # several finite windows, no browser renew
   config['services'][0]['name']='pending'
   saved=cli({'action':'save','expected_revision':1,'config':config});assert saved['active_revision']==1 and saved['saved_revision']==2 and saved['pending_config']['apply_required']
   assert saved['active_config']['services'][1]['name']=='original';tls()
   status=call({'action':'status'});assert status['runtime']['generation']==generation and status['desired_state']['state']=='enabled'
   stopped=call({'action':'stop'});assert stopped['desired_state']['manual_stop_latch'] and stopped['runtime']['phase']=='stopped',stopped
   assert absent() and not (d/'runtime').exists()
   old=call({'action':'event','generation':generation});assert old['desired_state']['manual_stop_latch'] and absent()
   restarted=call({'action':'start','revision':2,'approved':True});assert restarted['runtime']['phase']=='running',restarted
   assert restarted['runtime']['generation']>generation
   cli({'action':'stop'}) # separate process revokes intent; controller cleans it
   time.sleep(.4)
   stopped=call({'action':'status'});assert stopped['runtime']['phase']=='stopped' and absent(),stopped
   config['services'][0]['name']='after-stop';cli({'action':'save','expected_revision':2,'config':config});time.sleep(.25);assert absent()
   final=cli({'action':'status'});assert final['desired_state']['state']=='disabled' and final['runtime']['phase']=='stopped'
   call({'action':'exit'});p.wait(timeout=3);assert p.returncode==0,p.stderr.read()
   print('PASS controller: Save inactive; approval; actual guarded TLS; autonomous finite renew; running Save pending; durable Stop; stale generation latch; source cleanup')
  finally:
   if p and p.poll() is None:p.kill();p.wait(timeout=3)
   if p:print(p.stderr.read(),flush=True)
   backend.shutdown();backend.server_close();thread.join(3)
 assert not pathlib.Path(td).exists()
if __name__=='__main__':main()
