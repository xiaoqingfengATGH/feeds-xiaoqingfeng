import sys,json,shlex,subprocess,time,hashlib
from p5_resume_support import *
def req(q):return json.loads(remote('lua /root/homepublish-p5/four-cli.lua',json.dumps(q).encode()))
def ubus(m,d):return remote('ubus call service '+m+' '+shlex.quote(json.dumps(d)))
log=[]; held=None
try:
 remote("umask 077; mkdir -p /root/homepublish-p5/auth; chmod 700 /root/homepublish-p5 /root/homepublish-p5/auth; dropbearkey -t ed25519 -f /root/homepublish-p5/auth/host >/dev/null 2>&1; dropbearkey -t ed25519 -f /root/homepublish-p5/auth/client > /root/homepublish-p5/auth/client.pub 2>/dev/null; sed -n '/^ssh-ed25519 /p' /root/homepublish-p5/auth/client.pub > /root/homepublish-p5/auth/authorized_keys; chmod 600 /root/homepublish-p5/auth/*")
 remote("lua -e \"package.path='/usr/share/homepublish/?.lua;'..package.path;local s=assert(require('device-integrations').certificate_source('acme:home_rsa','home.iwonderful.top'));local f=assert(io.open('/root/homepublish-p5/tls-backend.sh','w'));f:write('#!/bin/sh\\nexec /usr/bin/openssl s_server -quiet -rev -accept 127.0.0.1:50886 -cert '..s.certificate..' -key '..s.key..'\\n');f:close()\"")
 instances={'web':{'command':['/usr/sbin/nginx','-p','/root/homepublish-p5/','-c','backend.conf']},'tls':{'command':['/bin/sh','/root/homepublish-p5/tls-backend.sh']},'ssh':{'command':['/usr/sbin/dropbear','-F','-E','-s','-j','-k','-r','/root/homepublish-p5/auth/host','-D','/root/homepublish-p5/auth','-p','127.0.0.1:50887','-P','/root/homepublish-p5/auth/pid','-c','printf P5_NATIVE_SSH_AUTH_GREEN']},'raw':{'command':['/usr/bin/socat','TCP-LISTEN:50888,bind=127.0.0.1,reuseaddr,fork','EXEC:/bin/cat']}}
 ubus('set',{'name':'homepublish-p5-backend','instances':{k:v for k,v in instances.items() if k!='tls'}});time.sleep(2)
 c=req({'action':'fixture_config'});s=req({'action':'status'});s=req({'action':'save','expected_revision':s['saved_revision'],'config':c})
 failed=req({'action':'start','revision':s['saved_revision'],'approved':True});log.append({'real_tls_backend_absent':failed})
 assert failed['runtime']['phase']!='running' and not failed['runtime']['active_verified'],failed
 assert failed['runtime']['cleanup']=='confirmed',failed
 remote('test ! -e /tmp/homepublish-runtime')
 assert req({'action':'stop'})['runtime']['cleanup']=='confirmed'
 ubus('set',{'name':'homepublish-p5-backend','instances':instances});time.sleep(2)
 a=req({'action':'start','revision':s['saved_revision'],'approved':True});log.append(a);assert a['runtime']['phase']=='running',a
 assert all(v['ready'] for v in a['runtime']['services'].values())
 assert remote("env -u CURL_CA_BUNDLE -u SSL_CERT_FILE -u SSL_CERT_DIR curl -q --noproxy '*' --fail --silent --max-time 4 --resolve home.iwonderful.top:50881:192.168.1.2 https://home.iwonderful.top:50881/")=='P5_PRODUCTION_A'
 out=remote("dbclient -y -y -i /root/homepublish-p5/auth/client -p 50881 root@192.168.1.2 ignored 2>/root/homepublish-p5/ssh-client.log");assert out=='P5_NATIVE_SSH_AUTH_GREEN',out
 # Target Python is not assumed: controller-side TLS clients use SSH-owned forwards only.
 tunnel=subprocess.Popen(SSH[:-1]+['-N','-L','127.0.0.1:51881:192.168.1.2:50881',SSH[-1]],stdout=subprocess.PIPE,stderr=subprocess.PIPE)
 try:
  import socket,ssl
  time.sleep(1)
  context=ssl.create_default_context();https=context.wrap_socket(socket.create_connection(('127.0.0.1',51881),4),server_hostname='home.iwonderful.top');https.settimeout(5)
  https.sendall(b'GET / HTTP/1.1\r\nHost: home.iwonderful.top\r\nConnection: keep-alive\r\n\r\n');data=https.recv(4096);assert b'P5_PRODUCTION_A' in data,data
  opaque=ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT);opaque.check_hostname=False;opaque.verify_mode=ssl.CERT_NONE
  tls=opaque.wrap_socket(socket.create_connection(('127.0.0.1',51881),4),server_hostname='opaque.home.test');tls.settimeout(5)
  payload=b'P5_OPAQUE_binary_0123456789';tls.sendall(payload+b'\n');assert tls.recv(4096).strip()==payload[::-1]
  for name in ['wrong.home.test',None]:
   try:
    bad=opaque.wrap_socket(socket.create_connection(('127.0.0.1',51881),4),server_hostname=name);bad.settimeout(4);bad.sendall(payload+b'\n');result=bad.recv(4096);bad.close();assert result==b'',(name,result)
   except (ssl.SSLError,ConnectionError):pass
  assert req({'action':'stop'})['runtime']['cleanup']=='confirmed'
  for label,sock in [('https',https),('tls',tls)]:
   try: result=sock.recv(4096);assert result==b'',(label,result)
   except (ConnectionResetError,ssl.SSLEOFError):pass
   sock.close();log.append({label+'_held_stop_eof':True})
 finally:
  tunnel.terminate();tunnel.communicate(timeout=10)
 print('P5_TLS_TRANSPARENCY_NEGATIVE_SNI_HTTPS_TLS_EOF_NATIVE_SSH_GREEN')
finally:
 try:log.append(req({'action':'stop'}))
 finally:
  ubus('delete',{'name':'homepublish-p5-backend'});time.sleep(2)
  remote('rm -rf /root/homepublish-p5/auth; rm -f /root/homepublish-p5/tls-backend.sh; test ! -e /tmp/homepublish-runtime; sha256sum /etc/homepublish/product/state; ubus call service list \'{"name":"homepublish-runtime"}\'')
  (E/'four-complete-lifecycle.json').write_text(json.dumps(log,indent=2))
