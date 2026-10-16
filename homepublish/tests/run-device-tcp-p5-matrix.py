import json,shlex,hashlib,time
from p5_resume_support import R,E,remote,upload
BASE='6995a844e18ac2c9182b3e4f8035138ebe561aee168530d43c550d5ee14be7d1'
log=[]
def req(q):return json.loads(remote('lua /root/homepublish-p5/matrix-cli.lua',json.dumps(q).encode()))
def ubus(m,d):return remote('ubus call service '+m+' '+shlex.quote(json.dumps(d)))
def check_live():assert remote('sha256sum /etc/homepublish/product/state').split()[0]==BASE

def config(infam,backfam,types):
 addr='192.168.1.2' if infam=='ipv4' else 'fd89:878e:a47f::1'
 host='127.0.0.1' if backfam=='ipv4' else 'fd89:878e:a47f::1'
 services=[]
 for typ,port in [('https_proxy',50882),('tls_passthrough',50886),('ssh',50887),('tcp_forward',50888)]:
  if typ not in types:continue
  s=dict(service_id=typ,name=typ,enabled=True,type=typ,backend=dict(addressFamily=backfam,host=host,port=port,allowed_ranges=['127.0.0.0/8'] if backfam=='ipv4' else ['fd89:878e:a47f::1/128']),authentication_review=dict(authentication='confirmed',management=False))
  if typ=='https_proxy':s.update(hostname='home.iwonderful.top',certificate_mode='inherit',upstream_scheme='http')
  if typ=='tls_passthrough':s['hostname']='opaque.home.test'
  if typ=='tcp_forward':s['listen_port']=50885
  services.append(s)
 c=dict(schema_version=2,access_profile=dict(listeners=[dict(listener_id='matrix',family=infam,network='lan',address=addr,port=50881)]),publication_policy=dict(mode='continuous',boot_restore=False),services=services)
 if 'https_proxy' in types:c['default_certificate_ref']='acme:home.iwonderful.top'
 return c,addr

def traffic(addr,types):
 endpoint='['+addr+']' if ':' in addr else addr
 if 'https_proxy' in types:
  assert remote("env -u CURL_CA_BUNDLE -u SSL_CERT_FILE -u SSL_CERT_DIR curl -q --noproxy '*' --fail --silent --max-time 6 --resolve "+shlex.quote('home.iwonderful.top:50881:'+endpoint)+' https://home.iwonderful.top:50881/')=='P5_MATRIX_WEB'
 if 'tls_passthrough' in types:
  out=remote("printf 'P5_MATRIX_OPAQUE\\n' | timeout 7 openssl s_client -quiet -connect "+shlex.quote(endpoint+':50881')+" -servername opaque.home.test 2>/dev/null; rc=$?; test $rc -eq 0 -o $rc -eq 124")
  assert 'EUQAPO_XIRTAM_5P' in out,out
 if 'ssh' in types:
  out=remote('dbclient -y -y -i /root/homepublish-p5/matrix-auth/client -p 50881 root@'+addr+' ignored 2>/root/homepublish-p5/matrix-ssh.log');assert out=='P5_MATRIX_SSH_AUTH',out
 if 'tcp_forward' in types:
  code="local n=require('nixio');local s=assert(n.socket('"+('inet6' if ':' in addr else 'inet')+"','stream'));s:setopt('socket','rcvtimeo',5);assert(s:connect('"+addr+"',50885));assert(s:send('P5_MATRIX_RAW')==13);assert(s:recv(13)=='P5_MATRIX_RAW');s:close();print('P5_MATRIX_RAW_GREEN')"
  remote('lua -e '+shlex.quote(code))

try:
 check_live();remote("test ! -e /tmp/homepublish-runtime; test ! -e /root/homepublish-p5/matrix-auth; umask 077; mkdir -p /root/homepublish-p5/matrix-auth; chmod 700 /root/homepublish-p5/matrix-auth; dropbearkey -t ed25519 -f /root/homepublish-p5/matrix-auth/host >/dev/null 2>&1; dropbearkey -t ed25519 -f /root/homepublish-p5/matrix-auth/client > /root/homepublish-p5/matrix-auth/client.pub 2>/dev/null; sed -n '/^ssh-ed25519 /p' /root/homepublish-p5/matrix-auth/client.pub > /root/homepublish-p5/matrix-auth/authorized_keys; chmod 600 /root/homepublish-p5/matrix-auth/*")
 upload(R/'homepublish/tests/device-tcp-p5-matrix-cli.lua','/root/homepublish-p5/matrix-cli.lua')
 assert remote('sha256sum /root/homepublish-p5/matrix-cli.lua').split()[0]==hashlib.sha256((R/'homepublish/tests/device-tcp-p5-matrix-cli.lua').read_bytes()).hexdigest()
 for bf in ['ipv4','ipv6']:
  host='127.0.0.1' if bf=='ipv4' else '[fd89:878e:a47f::1]'
  conf='daemon off; master_process off; pid /root/homepublish-p5/matrix-backend.pid; error_log /root/homepublish-p5/matrix-backend.log; events {} http { access_log off; server { listen '+host+':50882; location / { return 200 "P5_MATRIX_WEB"; } } }'
  remote('cat > /root/homepublish-p5/matrix-backend.conf',conf.encode())
  code="package.path='/usr/share/homepublish/?.lua;'..package.path;local s=assert(require('device-integrations').certificate_source('acme:home.iwonderful.top','home.iwonderful.top'));local f=assert(io.open('/root/homepublish-p5/matrix-tls.sh','w'));f:write('#!/bin/sh\\nexec openssl s_server -quiet -rev -accept "+host+":50886 -cert '..s.certificate..' -key '..s.key..'\\n');f:close()"
  remote('lua -e '+shlex.quote(code))
  tcp='TCP4-LISTEN:50888,bind=127.0.0.1,reuseaddr,fork' if bf=='ipv4' else 'TCP6-LISTEN:50888,bind=[fd89:878e:a47f::1],ipv6only=1,reuseaddr,fork'
  instances={'web':{'command':['/usr/sbin/nginx','-p','/root/homepublish-p5/','-c','matrix-backend.conf']},'tls':{'command':['/bin/sh','/root/homepublish-p5/matrix-tls.sh']},'ssh':{'command':['/usr/sbin/dropbear','-F','-E','-s','-j','-k','-r','/root/homepublish-p5/matrix-auth/host','-D','/root/homepublish-p5/matrix-auth','-p',host+':50887','-P','/root/homepublish-p5/matrix-auth/pid','-c','printf P5_MATRIX_SSH_AUTH']},'raw':{'command':['/usr/bin/socat',tcp,'EXEC:/bin/cat']}}
  ubus('set',dict(name='homepublish-p5-matrix-backend',instances=instances));time.sleep(2)
  cases=[(i,['https_proxy','tls_passthrough','ssh','tcp_forward']) for i in ['ipv4','ipv6']]
  if bf=='ipv6':cases += [('ipv6',t+['tcp_forward']) for t in [['tls_passthrough'],['ssh'],['tls_passthrough','ssh']]]
  for infam,types in cases:
   c,addr=config(infam,bf,types);s=req({'action':'status'});s=req(dict(action='save',expected_revision=s['saved_revision'],config=c));assert 'saved_revision' in s,s
   a=req(dict(action='start',revision=s['saved_revision'],approved=True));assert a['runtime']['phase']=='running',a
   assert all(x['ready'] for x in a['runtime']['services'].values()),a
   traffic(addr,types)
   stopped=req({'action':'stop'});assert stopped['runtime']['cleanup']=='confirmed',stopped
   remote('test ! -e /tmp/homepublish-runtime');check_live()
   log.append(dict(ingress=infam,ingress_address=addr,backend=bf,backend_address='127.0.0.1' if bf=='ipv4' else 'fd89:878e:a47f::1',types=types,all_ready=True,traffic=True,cleanup='confirmed'))
   (E/'final-matrix-results.json').write_text(json.dumps(log,indent=2))
  ubus('delete',dict(name='homepublish-p5-matrix-backend'));time.sleep(2)
 print('P5_FINAL_PRODUCTION_FAMILY_NO_HTTPS_MATRIX_GREEN')
finally:
 try:req({'action':'stop'})
 finally:
  current=json.loads(ubus('list',dict(name='homepublish-p5-matrix-backend')))
  if 'homepublish-p5-matrix-backend' in current:ubus('delete',dict(name='homepublish-p5-matrix-backend'))
  time.sleep(2)
  remote('rm -rf /root/homepublish-p5/matrix-auth; rm -f /root/homepublish-p5/matrix-tls.sh; test ! -e /tmp/homepublish-runtime; test ! -e /root/homepublish-p5/matrix-auth; ubus call service list \'{"name":"homepublish-runtime"}\'; ubus call service list \'{"name":"homepublish-p5-matrix-backend"}\'; netstat -lnt; sha256sum /etc/homepublish/product/state')
  check_live();(E/'final-matrix-results.json').write_text(json.dumps(log,indent=2))
