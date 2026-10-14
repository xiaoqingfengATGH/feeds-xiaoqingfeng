#!/usr/bin/env python3
"""Real two-service controller generation acceptance, non-installed loopback only."""
import copy, importlib.util, json, os, pathlib, select, socket, ssl, subprocess, tempfile, threading, time
spec=importlib.util.spec_from_file_location('single',pathlib.Path(__file__).with_name('test-controller.py'))
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
class V6(m.http.server.ThreadingHTTPServer): address_family=socket.AF_INET6

def main():
 with tempfile.TemporaryDirectory(prefix='controller-multi-',dir='/home/eric/homestun-sdk-check') as td:
  d=pathlib.Path(td);env={**os.environ,'LUA_CPATH':str(d/'?.so')};servers=[];threads=[];p=None
  try:
   for cls,addr,marker in [(m.http.server.ThreadingHTTPServer,'127.0.0.1',b'multi-v4'),(V6,'::1',b'multi-v6')]:
    s=cls((addr,0),m.Backend);s.marker=marker;s.count=0;servers.append(s);t=threading.Thread(target=s.serve_forever);t.start();threads.append(t)
   with socket.socket() as s:s.bind(('127.0.0.1',0));port=s.getsockname()[1]
   subprocess.run(['cc','-std=c99','-Wall','-Wextra','-Werror','-Wno-misleading-indentation','-fPIC','-shared','-I'+m.DEV+'/lua5.1','-I'+m.DEV+'/x86_64-linux-gnu','-DPRODUCT_ROOT='+json.dumps(str(d/'store')),str(m.SRC/'product-store.c'),'-o',str(d/'homepublish_store.so')],check=True)
   def cli(req):
    for _ in range(30):
     r=subprocess.run([m.LUA,str(m.SHARE/'product-cli.lua')],input='HP1'+m.wire(req),text=True,capture_output=True,env=env,timeout=3)
     if 'store busy' not in r.stderr:break
     time.sleep(.01)
    assert r.returncode==0,(r.stdout,r.stderr);return m.decode(r.stdout)
   services=[]
   for i,(host,addr) in enumerate([('service.home','127.0.0.1'),('second.home','fd00::3')]):
    services.append({'service_id':'fixture' if i==0 else 'second','name':host,'hostname':host,'backend':{'addressFamily':'ipv6' if i else 'ipv4','host':addr,'port':servers[i].server_port,'allowed_ranges':['127.0.0.0/8','fd00::/16']},'certificate_ref':'import:fixture' if i==0 else 'import:second','authentication_review':{'authentication':'confirmed','management':False}})
   config={'schema_version':1,'services':services,'access_profile':{'methods_allowed':['manual_ipv4','direct_ipv6'],'listeners':[{'family':f,'address':a,'interface':'fixture','zone':'fixture','protocol':'tcp','internal_port':port,'external_port':port} for f,a in [('ipv4','192.168.1.2'),('ipv6','fd00::2')]]}}
   def absent():
    for a in ['127.0.0.1','::1']:
     try:socket.create_connection((a,port),timeout=.1).close();return False
     except OSError:pass
    return True
   assert cli({'action':'save','expected_revision':0,'config':config})['saved_revision']==1 and absent()
   for i,host in enumerate(['service.home','second.home']):
    subprocess.run(['openssl','req','-x509','-newkey','rsa:2048','-nodes','-keyout',str(d/('key.pem' if i==0 else 'key2.pem')),'-out',str(d/('cert.pem' if i==0 else 'cert2.pem')),'-days','1','-subj','/CN='+host,'-addext','subjectAltName=DNS:'+host],check=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
   m.compile_adapter(d)
   p=subprocess.Popen([m.LUA,str(m.ROOT/'homepublish/tests/controller-host.lua'),str(m.SHARE),str(d),str(port),str(servers[0].server_port),str(servers[1].server_port)],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,env=env)
   def call(req):
    p.stdin.write('HP1'+m.wire(req)+'\n');p.stdin.flush();assert select.select([p.stdout],[],[],5)[0],'response timeout';line=p.stdout.readline();assert line,(p.poll(),p.stderr.read());return m.decode(line)
   started=call({'action':'start','revision':1,'approved':True});assert started.get('runtime',{}).get('phase')=='running',('multi-service controller missing',started)
   contexts=[ssl.create_default_context(cafile=str(d/name)) for name in ['cert.pem','cert2.pem']]
   def tls(index,marker,address='127.0.0.1',host=None):
    h=host or ['service.home','second.home'][index]
    with contexts[index].wrap_socket(socket.create_connection((address,port),timeout=.5),server_hostname=h) as s:
     s.sendall(('GET / HTTP/1.0\r\nHost: '+h+'\r\n\r\n').encode());data=b''
     while True:
      v=s.recv(4096)
      if not v:break
      data+=v
     assert marker in data,data
   def matrix(markers):
    for i,marker in enumerate(markers):
     for address in ['127.0.0.1','::1']:tls(i,marker,address)
   matrix([b'multi-v4',b'multi-v6'])
   ready=started['runtime']['services'];assert set(ready)=={'fixture','second'} and all(v['ready'] and v['generation']==started['runtime']['generation'] for v in ready.values()),ready
   try:tls(0,b'multi-v4',host='unknown.home');raise AssertionError('unknown SNI accepted')
   except ssl.SSLError:pass
   config['services'][0]['backend']={'addressFamily':'ipv6','host':'fd00::3','port':servers[1].server_port,'allowed_ranges':['fd00::/16']}
   saved=cli({'action':'save','expected_revision':1,'config':config});assert saved['active_revision']==1 and saved['pending_config']['apply_required'];matrix([b'multi-v4',b'multi-v6'])
   applied=call({'action':'apply','revision':2,'approved':True});assert applied['active_revision']==2 and applied['runtime']['generation']>started['runtime']['generation'];matrix([b'multi-v6',b'multi-v6'])
   config['services'].pop();cli({'action':'save','expected_revision':2,'config':config});tls(1,b'multi-v6')
   deleted=call({'action':'apply','revision':3,'approved':True});assert set(deleted['runtime']['services'])=={'fixture'};tls(0,b'multi-v6')
   try:tls(1,b'multi-v6');raise AssertionError('deleted service still served')
   except ssl.SSLError:pass
   config['services'].append(copy.deepcopy(services[1]) if len(services)>1 else {'service_id':'second','name':'second','hostname':'second.home','backend':{'addressFamily':'ipv6','host':'fd00::3','port':servers[1].server_port,'allowed_ranges':['fd00::/16']},'certificate_ref':'import:second','authentication_review':{'authentication':'confirmed','management':False}})
   cli({'action':'save','expected_revision':3,'config':config});call({'action':'fault','stage':'second-readiness'})
   failed=call({'action':'apply','revision':4,'approved':True});assert failed['active_revision']==3 and failed['attempted_revision']==4 and failed['runtime']['phase']=='blocked' and not failed['runtime']['active_verified'] and absent(),failed
   assert failed['runtime']['services']['fixture']['ready'] and not failed['runtime']['services']['second']['ready'],failed
   call({'action':'fault','stage':'none'});call({'action':'stop'})
   config['publication_policy']={'mode':'temporary','temporary_duration':60,'boot_restore':False}
   cli({'action':'save','expected_revision':4,'config':config});first=call({'action':'start','revision':5,'approved':True});expiry=first['runtime']['expires_at'];matrix([b'multi-v6',b'multi-v6'])
   cli({'action':'save','expected_revision':5,'config':config});assert call({'action':'apply','revision':6,'approved':True})['runtime']['expires_at']==expiry
   streams=[]
   for i,address in enumerate(['127.0.0.1','::1']):
    stream=contexts[i].wrap_socket(socket.create_connection((address,port),timeout=1),server_hostname=['service.home','second.home'][i])
    stream.sendall(('GET /stream HTTP/1.0\r\nHost: '+['service.home','second.home'][i]+'\r\n\r\n').encode())
    data=b''
    while b'tick-' not in data:data+=stream.recv(4096)
    streams.append(stream)
   stopped=call({'action':'stop'});assert stopped['runtime']['phase']=='stopped' and not stopped['runtime']['active_verified'] and absent() and not (d/'runtime').exists()
   for stream in streams:
    end=time.monotonic()+1;ended=False
    while time.monotonic()<end:
     try:data=stream.recv(4096)
     except (ssl.SSLError,OSError):data=b''
     if not data:ended=True;break
    stream.close();assert ended,'Stop left established stream live'
   call({'action':'exit'});p.wait(timeout=3);assert p.returncode==0,p.stderr.read()
   assert all(s.count>0 for s in servers)
   print('PASS multi-controller: independent SAN/key TLS; 4 ingress/backend combinations; exact per-service generation readiness; Save pending; whole-generation Apply; deleted SNI rejected; second readiness failure closes all; original temporary deadline; Stop dual listeners/native runtime absent')
  finally:
   if p and p.poll() is None:p.kill();p.wait(timeout=3)
   if p:print(p.stderr.read())
   for s in servers:s.shutdown();s.server_close()
   for t in threads:t.join(3)
 assert not pathlib.Path(td).exists()
if __name__=='__main__':main()
