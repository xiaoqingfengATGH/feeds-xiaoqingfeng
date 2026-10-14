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
 def do_GET(self):
  self.server.count+=1;self.send_response(200);self.end_headers()
  if self.path=='/stream':
   try:
    for i in range(800):self.wfile.write(f'tick-{i}\n'.encode());self.wfile.flush();time.sleep(.2)
   except (BrokenPipeError,ConnectionResetError):pass
  else:self.wfile.write(self.server.marker)
def compile_adapter(d):
 files=['lib/libc.so','usr/sbin/nginx','usr/lib/libpcre2-8.so.0.11.2','usr/lib/libssl.so.3','usr/lib/libcrypto.so.3','usr/lib/libz.so.1.3.1','lib/libgcc_s.so.1']
 names=['loader','nginx','libpcre2-8.so.0','libssl.so.3','libcrypto.so.3','libz.so.1','libgcc_s.so.1']
 header=d/'trusted-profile.h'
 rows=['{'+json.dumps(f)+','+json.dumps(n)+','+json.dumps(hashlib.sha256((SDK/f).read_bytes()).hexdigest())+'}' for f,n in zip(files,names)]
 header.write_text('#define HP_TRUST_ROOT '+json.dumps(str(SDK))+'\nstatic const struct hp_trust_entry hp_trust_entries[]={'+','.join(rows)+'};\n')
 vals={'HP_NGINX_LOADER':SDK/'lib/ld-musl-x86_64.so.1','HP_NGINX_EXEC':SDK/'usr/sbin/nginx','HP_NGINX_LIBS':str(SDK/'lib')+':'+str(SDK/'usr/lib'),'HP_NGINX_PREFIX':d,'HP_FOREIGN_SOCKET':d/'foreign.sock'}
 subprocess.run(['cc','-std=c11','-Wall','-Wextra','-Werror','-fPIC','-shared','-DHP_GUARD_TEST','-DHP_CONTROLLER_MULTI_TEST','-I'+str(SRC),'-I'+DEV+'/lua5.1','-I'+DEV+'/x86_64-linux-gnu',*['-D'+k+'='+json.dumps(str(v)) for k,v in vals.items()],'-DHP_TRUST_PROFILE_HEADER='+json.dumps(str(header)),str(SRC/'trusted-nginx.c'),str(SRC/'renewable-guard.c'),str(ROOT/'homepublish/tests/controller-adapter.c'),'-o',str(d/'homepublish_controller_test.so'),'-l:libcrypto.so.3'],check=True)
def main():
 assert (SHARE/'product-controller.lua').exists(),'internal runnable controller missing'
 with tempfile.TemporaryDirectory(prefix='controller-',dir='/home/eric/homestun-sdk-check') as td:
  d=pathlib.Path(td);env={**os.environ,'LUA_CPATH':str(d/'?.so')}
  subprocess.run(['cc','-std=c99','-Wall','-Wextra','-Werror','-Wno-misleading-indentation','-fPIC','-shared','-I'+DEV+'/lua5.1','-I'+DEV+'/x86_64-linux-gnu','-DPRODUCT_ROOT='+json.dumps(str(d/'store')),str(SRC/'product-store.c'),'-o',str(d/'homepublish_store.so')],check=True)
  def cli(req,ok=True):
   for _ in range(30):
    p=subprocess.run([LUA,str(SHARE/'product-cli.lua')],input='HP1'+wire(req),text=True,capture_output=True,env=env,timeout=3)
    if 'store busy' not in p.stderr:break # lock rejected before mutation
    time.sleep(.01)
   assert (p.returncode==0)==ok,(p.stdout,p.stderr)
   return decode(p.stdout) if ok else p.stderr
  backend=http.server.ThreadingHTTPServer(('127.0.0.1',0),Backend);backend.count=0;backend.marker=b'controller-real-backend'
  backend2=http.server.ThreadingHTTPServer(('127.0.0.1',0),Backend);backend2.count=0;backend2.marker=b'controller-second-backend'
  thread=threading.Thread(target=backend.serve_forever);thread.start();thread2=threading.Thread(target=backend2.serve_forever);thread2.start();p=None
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
   p=subprocess.Popen([LUA,str(ROOT/'homepublish/tests/controller-host.lua'),str(SHARE),str(d),str(port),str(backend.server_port),str(backend2.server_port)],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,env=env)
   def call(req):
    p.stdin.write('HP1'+wire(req)+'\n');p.stdin.flush();assert select.select([p.stdout],[],[],4)[0],'controller response timeout'
    line=p.stdout.readline();assert line,(p.poll(),p.stderr.read());return decode(line)
   rejected=call({'action':'start','revision':1,'approved':False});assert rejected['error']=='approval required' and absent()
   started=call({'action':'start','revision':1,'approved':True});assert started['runtime']['phase']=='running',started
   generation=started['runtime']['generation']
   ctx=ssl.create_default_context(cafile=str(d/'cert.pem'))
   def tls(marker=b'controller-real-backend'):
    with ctx.wrap_socket(socket.create_connection(('127.0.0.1',port),timeout=.4),server_hostname='service.home') as s:
     s.sendall(b'GET / HTTP/1.0\r\nHost: service.home\r\n\r\n');data=b''
     while True:
      v=s.recv(4096)
      if not v:break
      data+=v
     assert marker in data,data
    return data
   deadline=time.monotonic()+3
   while True:
    try:tls();break
    except (ConnectionRefusedError,ssl.SSLError):
     if time.monotonic()>=deadline:raise
     time.sleep(.02)
   time.sleep(1.4);tls() # several finite windows, no browser renew
   config['services'][0]['name']='pending'
   config['services'][0]['backend']['port']=backend2.server_port
   saved=cli({'action':'save','expected_revision':1,'config':config});assert saved['active_revision']==1 and saved['saved_revision']==2 and saved['pending_config']['apply_required']
   assert saved['active_config']['services'][1]['name']=='original';tls()
   status=call({'action':'status'});assert status['runtime']['generation']==generation and status['desired_state']['state']=='enabled'
   denied=call({'action':'apply','revision':1,'approved':True});assert denied['error']=='revision conflict';tls()
   denied=call({'action':'apply','revision':2,'approved':False});assert denied['error']=='approval required';tls()
   applied=call({'action':'apply','revision':2,'approved':True})
   assert applied['runtime']['phase']=='running' and applied['active_revision']==2 and not applied['pending_config']['apply_required'],applied
   assert applied['runtime']['generation']>generation
   tls(b'controller-second-backend')
   assert backend.count>0 and backend2.count>0
   assert cli({'action':'status'})['active_revision']==2
   stopped=call({'action':'stop'});assert stopped['desired_state']['manual_stop_latch'] and stopped['runtime']['phase']=='stopped',stopped
   assert absent() and not (d/'runtime').exists()
   old=call({'action':'event','generation':generation});assert old['desired_state']['manual_stop_latch'] and absent()
   restarted=call({'action':'start','revision':2,'approved':True});assert restarted['runtime']['phase']=='running',restarted
   assert restarted['runtime']['generation']>generation
   plugin=ROOT/'luci-app-homepublish/root/usr/libexec/rpcd/homepublish'
   script=plugin.read_text().replace('/usr/bin/lua',LUA).replace('/usr/share/homepublish',str(SHARE))
   rpc_plugin=d/'rpc-homepublish';rpc_plugin.write_text(script);rpc_plugin.chmod(0o755)
   revoked=subprocess.run([str(rpc_plugin),'call','stop'],input='{}',text=True,capture_output=True,env=env,timeout=3)
   assert revoked.returncode==0,(revoked.stdout,revoked.stderr)
   revoked=json.loads(revoked.stdout)
   assert revoked['desired_state']['manual_stop_latch'] and revoked['runtime']['phase']=='cleanup_required',revoked
   time.sleep(.4)
   stopped=call({'action':'status'});assert stopped['runtime']['phase']=='stopped' and absent(),stopped
   config['services'][0]['name']='after-stop';cli({'action':'save','expected_revision':2,'config':config});time.sleep(.25);assert absent()
   final=cli({'action':'status'});assert final['desired_state']['state']=='disabled' and final['runtime']['phase']=='stopped'
   # Adapter and readiness failures retain attempted, never claim new active.
   for stage in ('start','readiness','cleanup'):
    call({'action':'fault','stage':stage})
    failed=call({'action':'start','revision':3,'approved':True})
    if stage=='cleanup':
     # successful start then Stop response cannot assert cleanup when adapter says unknown
     assert failed['runtime']['phase']=='running',failed
     failed=call({'action':'stop'})
     assert failed['runtime']['cleanup']=='unknown',failed
     assert 'busy' in call({'action':'start','revision':3,'approved':True})['error']
    else:
     assert failed['runtime']['phase']=='blocked' and failed['runtime']['stage']==stage,failed
     assert failed['active_revision']==2 and failed['attempted_revision']==3 and not failed['runtime']['active_verified'],failed
     cross=cli({'action':'status'});assert cross['runtime']['phase']=='blocked' and cross['pending_config']['apply_required']
    assert absent()
    call({'action':'fault','stage':'none'});call({'action':'stop'})
   call({'action':'start','revision':3,'approved':True})
   cli({'action':'save','expected_revision':3,'config':config})
   call({'action':'fault','stage':'readiness'})
   failed=call({'action':'apply','revision':4,'approved':True})
   assert failed['active_revision']==3 and failed['attempted_revision']==4 and failed['candidate_revision']==4 and not failed['runtime']['active_verified'] and failed['runtime']['phase']=='blocked' and absent(),failed
   cross=cli({'action':'status'});assert cross['pending_config']['apply_required'] and cross['runtime']['cleanup']=='confirmed'
   call({'action':'fault','stage':'none'});call({'action':'stop'})
   assert absent()
   # Minimum canonical policy is a real 60s session, not a shortened fixture clock.
   config['publication_policy']={'mode':'temporary','temporary_duration':60,'boot_restore':False}
   temp=cli({'action':'save','expected_revision':4,'config':config});assert temp['saved_revision']==5
   first=call({'action':'start','revision':5,'approved':True});expiry=first['runtime']['expires_at']
   time.sleep(1.2);config['services'][0]['backend']['port']=backend.server_port
   saved=cli({'action':'save','expected_revision':5,'config':config});assert saved['runtime']['expires_at']==expiry
   tls(b'controller-second-backend')
   switched=call({'action':'apply','revision':6,'approved':True});assert switched['runtime']['expires_at']==expiry and switched['runtime']['active_verified'],switched
   tls()
   stream=ctx.wrap_socket(socket.create_connection(('127.0.0.1',port),timeout=2),server_hostname='service.home')
   stream.sendall(b'GET /stream HTTP/1.0\r\nHost: service.home\r\n\r\n')
   seen=0;last=0;ended=False
   while time.time()<expiry+2:
    try:v=stream.recv(4096)
    except (ssl.SSLError,OSError):v=b''
    if not v:ended=True;break
    if b'tick-' in v:seen+=1;last=time.time()
   stream.close();print('expiry evidence: received_chunks=',seen,'last_tick=',last,'original_deadline=',expiry,flush=True);assert ended and seen>10 and last>=expiry-2,(ended,seen,last,expiry)
   time.sleep(.25);expired=call({'action':'status'})
   assert expired['runtime']['expires_at']==expiry and expired['desired_state']['state']=='disabled' and expired['runtime']['phase']=='stopped' and absent(),expired
   assert not (d/'runtime').exists()
   old=call({'action':'event','generation':switched['runtime']['generation']});assert absent() and old['desired_state']['manual_stop_latch']
   # Data source remains live beyond proxy deadline.
   with socket.create_connection(('127.0.0.1',backend.server_port),timeout=1) as source:
    source.sendall(b'GET / HTTP/1.0\r\n\r\n');assert b'200' in source.recv(1024)
   print('PASS controller apply: two backend markers/counters; revision/approval; failures start/readiness/cleanup; 60s original deadline; live stream and new listener closed')
   call({'action':'exit'});p.wait(timeout=3);assert p.returncode==0,p.stderr.read()
   print('PASS controller: Save inactive; approval; actual guarded TLS; autonomous finite renew; running Save pending; durable Stop; stale generation latch; source cleanup')
  finally:
   if p and p.poll() is None:p.kill();p.wait(timeout=3)
   if p:print(p.stderr.read(),flush=True)
   backend.shutdown();backend.server_close();thread.join(3)
   backend2.shutdown();backend2.server_close();thread2.join(3)
 assert not pathlib.Path(td).exists()
if __name__=='__main__':main()
