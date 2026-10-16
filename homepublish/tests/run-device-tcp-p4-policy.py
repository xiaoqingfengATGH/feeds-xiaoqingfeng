#!/usr/bin/env python3
"""Remote-only task21 test; local Python is transport and assertion driver."""
import hashlib,json,pathlib,subprocess,sys,time
ROOT=pathlib.Path(__file__).resolve().parents[2]
E=ROOT/'docs/evidence/tcp-p4';E.mkdir(parents=True,exist_ok=True)
SSH=['ssh','-o','ProxyCommand=none','-o','ProxyJump=none','-o','IdentitiesOnly=yes','-o','BatchMode=yes','-i','D:/DevPortal/CloudHosts/HomePri.key','-p','222','root@127.0.0.1']
SCP=['scp','-O','-o','ProxyCommand=none','-o','ProxyJump=none','-o','IdentitiesOnly=yes','-o','BatchMode=yes','-i','D:/DevPortal/CloudHosts/HomePri.key','-P','222']
REMOTE='/tmp/homepublish-tcp-p3'
INSTALLED=True
def ssh(cmd,data=None,check=True):
 r=subprocess.run(SSH+[cmd],input=data,text=True,capture_output=True,timeout=100)
 if check and r.returncode: raise RuntimeError((cmd,r.returncode,r.stdout,r.stderr))
 return r
files=list((ROOT/'homepublish/files/usr/share/homepublish').glob('*.lua'))+[ROOT/'homepublish/tests/device-tcp-p3-controller-cli.lua',ROOT/'homepublish/tests/device-tcp-p3-controller-adapter.lua',ROOT/'homepublish/tests/device-tcp-p4-policy-rpc.lua']
for f in files: subprocess.run(SCP+[str(f).replace('\\','/'),'root@127.0.0.1:'+REMOTE+'/'],check=True,capture_output=True)
if INSTALLED and '--deploy-supported' in sys.argv:
 names=['product-device-provider.lua','product-device-v2-profile.lua','product-v2-runtime.lua','product-procd-group.lua','product-controller.lua','direct-renderer.lua','tcp-route-plan.lua','tcp-stream-renderer.lua','sslh-renderer.lua']
 ssh('umask 077; mkdir -p /root/homepublish-p3-installed-backup')
 for name in names:
  ssh('test -e /root/homepublish-p3-installed-backup/'+name+' || { test ! -e /usr/share/homepublish/'+name+' || cp /usr/share/homepublish/'+name+' /root/homepublish-p3-installed-backup/'+name+'; }; cp '+REMOTE+'/'+name+' /usr/share/homepublish/'+name+'; chmod 0644 /usr/share/homepublish/'+name)
 for f in files:
  if f.name in names:assert ssh('sha256sum /usr/share/homepublish/'+f.name).stdout.split()[0]==hashlib.sha256(f.read_bytes()).hexdigest()
subprocess.run(SCP+['C:/Users/xiaoq/AppData/Local/hermes/profiles/ta/cache/scratch/tcp-p3-controller-store.so','root@127.0.0.1:'+REMOTE+'/homepublish_store.so'],check=True,capture_output=True)
def request(q):
 r=ssh('lua '+REMOTE+('/device-tcp-p4-policy-rpc.lua' if INSTALLED else '/device-tcp-p3-controller-cli.lua'),json.dumps(q));print(r.stdout.strip());return json.loads(r.stdout)
c={'schema_version':2,'access_profile':{'listeners':[{'listener_id':'v6','family':'ipv6','network':'lan','address':'fd89:878e:a47f::1','port':49543}]},'publication_policy':{'mode':'continuous','boot_restore':False},'services':[]}
for id,kind in [('tls','tls_passthrough'),('raw','tcp_forward')]:
 s={'service_id':id,'name':id,'enabled':True,'type':kind,'backend':{'addressFamily':'ipv4','host':'127.0.0.1','port':49546,'allowed_ranges':['127.0.0.0/8']},'authentication_review':{'authentication':'confirmed','management':False}}
 if id=='tls': s['hostname']='tls.fixture.home'
 else:s['listen_port']=49550
 c['services'].append(s)
if INSTALLED:
 c['default_certificate_ref']='acme:home_rsa'
 import copy
 web=copy.deepcopy(c['services'][0]);web.update(service_id='web',name='web',type='https_proxy',hostname='home.iwonderful.top',certificate_mode='inherit',upstream_scheme='http');web['backend']['port']=49545
 ssh_service=copy.deepcopy(c['services'][0]);ssh_service.update(service_id='ssh',name='ssh',type='ssh');del ssh_service['hostname'];ssh_service['backend']['port']=49547
 c['services'] += [web,ssh_service]
def wait_state(predicate, timeout=35):
 end=time.monotonic()+timeout
 while time.monotonic()<end:
  s=request({'action':'status'})
  if predicate(s):return s
  time.sleep(1)
 raise AssertionError(('timeout',s))
def exercise():
 c['publication_policy']={'mode':'temporary','temporary_duration':60,'boot_restore':False}
 worker={'name':'homepublish-p4-policy','instances':{'controller':{'command':['/usr/bin/lua',REMOTE+'/device-tcp-p4-policy-rpc.lua','serve'],'stdout':True,'stderr':True}}}
 ssh('ubus call service set '+repr(json.dumps(worker)));ssh('sleep 2')
 saved=request({'action':'save','expected_revision':0,'config':c});assert saved['saved_revision']==1,saved
 contract=request({'action':'status'});assert contract['capabilities']['start'] and contract['capabilities']['apply'],contract
 if '--contract-only' in sys.argv:return
 started=request({'action':'start','revision':1,'approved':True});assert started['runtime']['phase']=='running',started
 assert started['capabilities']['start'] and started['capabilities']['apply'],'command response capability disagrees with status'
 deadline=started['runtime']['expires_at'];generation=started['runtime']['generation']
 c['services'][2]['backend']['port']=49556
 pending=request({'action':'save','expected_revision':1,'config':c});assert pending['active_revision']==1 and pending['saved_revision']==2
 state=json.loads(ssh("ubus call service list '{\"name\":\"homepublish-p3-controller\"}'").stdout)
 pid=state['homepublish-p3-controller']['instances']['sslh']['pid']
 ssh('kill -9 '+str(pid))
 # No browser or status requests during autonomous renew/recovery.
 time.sleep(12)
 recovered=request({'action':'status'})
 assert recovered['runtime']['phase']=='running',recovered
 assert recovered['runtime']['generation']!=generation,recovered
 assert recovered['runtime']['expires_at']==deadline and recovered['active_revision']==1 and recovered['saved_revision']==2,recovered
 response=ssh("env -u CURL_CA_BUNDLE -u SSL_CERT_FILE -u SSL_CERT_DIR curl -q --noproxy '*' --max-time 4 --fail --silent --resolve 'home.iwonderful.top:49543:[::1]' https://home.iwonderful.top:49543/").stdout
 assert response=='HP_TASK21_WEB',response
 print('PASS real-clock background process-fault recovery active1 not pending2 original deadline')
 old_generation=recovered['runtime']['generation']
 applied=request({'action':'apply','revision':2,'approved':True})
 assert applied['runtime']['phase']=='running' and applied['runtime']['expires_at']==deadline,applied
 stale=request({'action':'stale_tick','generation':old_generation})
 assert stale['runtime']['generation']==applied['runtime']['generation'] and stale['active_revision']==2,stale
 print('PASS Apply preserves original temporary deadline; stale event cannot replace generation')
 clients={'name':'homepublish-p3-clients','instances':{}}
 for port in (49543,49550):
  cmd='exec openssl s_client -connect [::1]:%s -servername tls.fixture.home -CAfile %s/controller-fixture/tls.pem -verify_return_error -quiet -ign_eof >%s/controller-fixture/held-%s.log 2>&1'%(port,REMOTE,REMOTE,port)
  clients['instances']['held'+str(port)]={'command':['/bin/sh','-c',cmd],'stdout':True,'stderr':True}
 if INSTALLED:
  clients['instances']['heldweb']={'command':['/bin/sh','-c','exec openssl s_client -connect [::1]:49543 -servername home.iwonderful.top -verify_hostname home.iwonderful.top -CAfile /etc/ssl/certs/ca-certificates.crt -verify_return_error -quiet -ign_eof >'+REMOTE+'/controller-fixture/held-web.log 2>&1'],'stdout':True,'stderr':True}
  clients['instances']['heldssh']={'command':['/usr/bin/dbclient','-y','-y','-N','-i',REMOTE+'/controller-fixture/ssh-client.key','-p','49543','root@::1'],'stdout':True,'stderr':True}
 ssh('ubus call service set '+repr(json.dumps(clients)));ssh('sleep 2')
 clientstate=json.loads(ssh("ubus call service list '{\"name\":\"homepublish-p3-clients\"}'").stdout)
 assert all(v['running'] for v in clientstate['homepublish-p3-clients']['instances'].values())
 established=ssh('netstat -nt').stdout
 for port in (49543,49550):assert ':'+str(port)+' ' in established
 started_wait=time.monotonic();remaining=max(0,deadline-int(ssh('date +%s').stdout))+3
 time.sleep(remaining)
 expired=request({'action':'status'})
 assert expired['runtime']['phase']=='stopped' and expired['runtime']['cleanup']=='confirmed',expired
 assert not json.loads(ssh("ubus call service list '{\"name\":\"homepublish-p3-controller\"}'").stdout)
 clientstate=json.loads(ssh("ubus call service list '{\"name\":\"homepublish-p3-clients\"}'").stdout)
 assert all(not v['running'] for v in clientstate['homepublish-p3-clients']['instances'].values()),clientstate
 print('PASS natural temporary expiry closes all four previously held protocol sessions')
 assert ssh('test ! -e '+REMOTE+'/controller-runtime',check=False).returncode==0
 print('PASS elapsed-clock expiry with no polling, epoch',deadline,'wait_seconds',round(time.monotonic()-started_wait,2))
 c['publication_policy']={'mode':'continuous','boot_restore':False}
 saved=request({'action':'save','expected_revision':2,'config':c})
 started=request({'action':'start','revision':3,'approved':True});assert started['runtime']['phase']=='running',started
 boot=request({'action':'restore'});assert boot['runtime']['phase']=='stopped',boot
 time.sleep(4);assert request({'action':'status'})['runtime']['phase']=='stopped'
 print('PASS boot_restore default false stops approved active generation and never restores')
 started=request({'action':'start','revision':3,'approved':True});assert started['runtime']['phase']=='running',started
 for expected in range(1,5):
  old=started['runtime']['generation']
  state=json.loads(ssh("ubus call service list '{\"name\":\"homepublish-p3-controller\"}'").stdout)
  ssh('kill -9 '+str(state['homepublish-p3-controller']['instances']['sslh']['pid']))
  time.sleep(8)
  started=request({'action':'status'})
  if expected<=3:
   assert started['runtime']['phase']=='running' and started['runtime']['generation']!=old,started
   assert started['runtime']['attempt_count']==expected and 'expires_at' not in started['runtime'],started
  else:
   assert started['runtime']['phase']=='blocked' and started['runtime']['attempt_count']==3 and started['runtime']['reason']=='recovery budget exhausted',started
   assert started['runtime']['cleanup']=='confirmed' and not started['runtime'].get('next_retry'),started
 time.sleep(5)
 assert request({'action':'status'})['runtime']['phase']=='blocked'
 print('PASS continuous process faults exhaust exactly three controller-owned retries; no artificial deadline/no unbounded respawn')
 started=request({'action':'start','revision':3,'approved':True});assert started['runtime']['phase']=='running',started
 stopped=request({'action':'stop'});g=stopped['runtime']['generation'];assert stopped['desired_state']['manual_stop_latch']
 time.sleep(6)
 late=request({'action':'stale_tick','generation':g});assert late['runtime']['phase']=='stopped' and late['desired_state']['manual_stop_latch'],late
 print('PASS manual Stop persistent latch suppresses late event and background resurrection')
baseline_cmd='sha256sum /etc/homepublish/product/state /etc/config/firewall /etc/config/dropbear /etc/config/uhttpd /etc/config/passwall2 /etc/resolv.conf /etc/hosts /usr/sbin/nginx; netstat -lntp | grep -E "(/dropbear|/uhttpd|/xray)"'
baseline=ssh(baseline_cmd).stdout;(E/'task25-baseline.txt').write_text(baseline)
fixture=REMOTE+'/controller-fixture'
try:
 ssh('test ! -e '+fixture+' && umask 077; mkdir -p '+fixture)
 ssh('rm -rf '+REMOTE+'/controller-store') # fixed compiled test-only store
 if INSTALLED:ssh('touch '+fixture+'/authorized')
 ssh(('touch ' if '--stale' in sys.argv else 'rm -f ')+REMOTE+'/controller-stale-generation')
 ssh('openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj /CN=tls.fixture.home -addext subjectAltName=DNS:tls.fixture.home -keyout '+fixture+'/tls.key -out '+fixture+'/tls.pem >/dev/null 2>&1')
 conf='worker_processes 1; daemon off; pid backend.pid; error_log stderr error; events {worker_connections 32;} http {access_log off; client_body_temp_path body; proxy_temp_path proxy; fastcgi_temp_path fastcgi; uwsgi_temp_path uwsgi; scgi_temp_path scgi; server {listen 127.0.0.1:49546 ssl; ssl_certificate '+fixture+'/tls.pem; ssl_certificate_key '+fixture+"/tls.key; return 200 'HP_TASK21_BACKEND';}}"
 if INSTALLED:
  conf=conf[:-1]+" server {listen 127.0.0.1:49545; return 200 'HP_TASK21_WEB';} server {listen 127.0.0.1:49556; return 200 'HP_P4_WEB_B';}}"
  ssh('test ! -e /root/homepublish-p3-controller-auth && umask 077; mkdir /root/homepublish-p3-controller-auth; dropbearkey -t ed25519 -f '+fixture+'/ssh-host.key >'+fixture+'/host-public 2>&1; dropbearkey -t ed25519 -f '+fixture+'/ssh-client.key >'+fixture+'/client-public 2>&1; grep \'^ssh-ed25519 \' '+fixture+'/client-public > /root/homepublish-p3-controller-auth/authorized_keys; chmod 0600 /root/homepublish-p3-controller-auth/authorized_keys '+fixture+'/*.key')
  ssh("lua -e \"package.path='/usr/share/homepublish/?.lua;'..package.path;local s=assert(require('device-integrations').certificate_source('acme:home_rsa','home.iwonderful.top'));os.execute('sha256sum '..s.certificate..' '..s.key..'; ls -lnL '..s.certificate..' '..s.key)\" >"+fixture+'/source-before')
 ssh('cat > '+fixture+'/backend.conf',conf)
 ssh('cat > '+fixture+'/blocker.conf','daemon off; pid blocker.pid; error_log stderr error; events {} stream {server {listen [::1]:49543; return "";}}')
 backend={'name':'homepublish-p3-backend','instances':{'fixture':{'command':[REMOTE+'/nginx-private','-p',fixture+'/','-c','backend.conf'],'env':{'OPENSSL_CONF':'/dev/null'},'stdout':True,'stderr':True}}}
 if INSTALLED:
  backend['instances']['ssh']={'command':['/usr/sbin/dropbear','-F','-E','-s','-j','-k','-r',fixture+'/ssh-host.key','-D','/root/homepublish-p3-controller-auth','-P',fixture+'/ssh.pid','-p','127.0.0.1:49547','-c','echo HP_TASK21_SSH'],'stdout':True,'stderr':True}
 ssh('ubus call service set '+repr(json.dumps(backend)));ssh('sleep 1')
 exercise()
finally:
 # Preserve runtime diagnostics before cleanup and never remove unknown residuals.
 diag=ssh('cat '+REMOTE+'/controller-runtime/config-test.log 2>/dev/null; ubus call service list \'{"name":"homepublish-p3-controller"}\'',check=False)
 (E/'task25-final-procd.txt').write_text(diag.stdout)
 clean=request({'action':'stop'})
 for name in ('homepublish-p4-policy','homepublish-p3-clients','homepublish-p3-blocker','homepublish-p3-backend'):
  ssh('ubus call service delete '+repr(json.dumps({'name':name})),check=False)
 ssh('sleep 3')
 after=ssh(baseline_cmd).stdout;(E/'task25-baseline-after.txt').write_text(after)
 assert baseline==after,'live management/config baseline changed'
 assert clean['runtime']['cleanup']=='confirmed',clean
 assert '49543' not in ssh('netstat -lntp').stdout
 assert '49546' not in ssh('netstat -lntp').stdout
 assert '49550' not in ssh('netstat -lntp').stdout
 if INSTALLED:
  ssh("lua -e \"package.path='/usr/share/homepublish/?.lua;'..package.path;local s=assert(require('device-integrations').certificate_source('acme:home_rsa','home.iwonderful.top'));os.execute('sha256sum '..s.certificate..' '..s.key..'; ls -lnL '..s.certificate..' '..s.key)\" >"+fixture+'/source-after; cmp '+fixture+'/source-before '+fixture+'/source-after')
  ssh('rm -rf /root/homepublish-p3-controller-auth')
  print('PASS real business certificate/key source hashes + ownership/mode preserved server-only')
 ssh('rm -rf '+fixture)
 print('PASS final owned listeners absent; private keys removed; live journal/config/management baseline unchanged')
manifest={f.name:hashlib.sha256(f.read_bytes()).hexdigest() for f in files}
for name,digest in manifest.items():assert ssh('sha256sum '+REMOTE+'/'+name).stdout.split()[0]==digest,name
(E/'task25-source-sha256.json').write_text(json.dumps(manifest,indent=2))
if INSTALLED:
 installed={f.name:hashlib.sha256(f.read_bytes()).hexdigest() for f in files if f.name in ['product-device-provider.lua','product-device-v2-profile.lua','product-v2-runtime.lua','product-procd-group.lua','product-controller.lua','direct-renderer.lua','tcp-route-plan.lua','tcp-stream-renderer.lua','sslh-renderer.lua']}
 for name,digest in installed.items():assert ssh('sha256sum /usr/share/homepublish/'+name).stdout.split()[0]==digest,name
 (E/'task25-installed-source-sha256.json').write_text(json.dumps(installed,indent=2))
 print('P4_TASK25_BACKGROUND_POLICY_GREEN')
else: print('P3_TASK21_PROCD_VERTICAL_GREEN')
