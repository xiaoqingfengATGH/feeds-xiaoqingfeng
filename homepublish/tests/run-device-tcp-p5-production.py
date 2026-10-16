#!/usr/bin/env python3
"""Target-only production tracer and real HTTP rpcd session authorization.
No browser interception, auth file changes, keys/session IDs in logs or live journal writes.
Assumes installed P5 source and existing private native-store module from P3.
"""
import hashlib,json,pathlib,shlex,subprocess
ROOT=pathlib.Path(__file__).resolve().parents[2]
E=ROOT/'docs/evidence/tcp-p5';E.mkdir(parents=True,exist_ok=True)
SSH=['ssh','-o','ProxyCommand=none','-o','ProxyJump=none','-o','IdentitiesOnly=yes','-o','BatchMode=yes','-i','D:/DevPortal/CloudHosts/HomePri.key','-p','222','root@127.0.0.1']
log=[]
def remote(cmd,data=None):
 r=subprocess.run(SSH+[cmd],input=data,capture_output=True,timeout=90)
 if r.returncode:raise RuntimeError('target command failed: '+r.stderr.decode())
 return r.stdout.decode()
def passed(s):log.append('PASS '+s);print(log[-1])
def ubus(obj,method,data):
 s=remote('ubus call '+obj+' '+method+' '+shlex.quote(json.dumps(data)));return json.loads(s) if s.strip() else {}
def req(q):return json.loads(remote('lua /root/homepublish-p5/production-cli.lua',json.dumps(q).encode()))
def http(sid,method,args):
 payload={'jsonrpc':'2.0','id':1,'method':'call','params':[sid,'homepublish',method,args]}
 return json.loads(remote("curl -q --noproxy '*' --max-time 10 --silent -H 'Content-Type: application/json' --data-binary @- http://127.0.0.1/ubus",json.dumps(payload).encode()))
def marker(address='192.168.1.2',port=50881):
 ep='['+address+']' if ':' in address else address
 return remote("env -u CURL_CA_BUNDLE -u SSL_CERT_FILE -u SSL_CERT_DIR curl -q --noproxy '*' --max-time 4 --fail --silent --resolve "+shlex.quote('home.iwonderful.top:'+str(port)+':'+ep)+' https://home.iwonderful.top:'+str(port)+'/')
baseline=remote('sha256sum /etc/homepublish/product/state /etc/config/firewall /etc/config/dropbear /etc/config/uhttpd /etc/config/passwall2 /etc/resolv.conf /etc/hosts')
cert_cmd="lua -e \"package.path='/usr/share/homepublish/?.lua;'..package.path;local s=assert(require('device-integrations').certificate_source('acme:home_rsa','home.iwonderful.top'));os.execute('sha256sum '..s.certificate..' '..s.key..'; ls -lnL '..s.certificate..' '..s.key)\""
# Certificate/key identity/permissions stay on server, never exported as evidence.
remote('umask 077; '+cert_cmd+' > /root/homepublish-p5/business-source.before')
sessions=[];started=False
try:
 # Installed production modules and binary paths, only journal native module scoped.
 passed(remote('lua /root/homepublish-p5/production-cli.lua plan').strip())
 c=req({'action':'fixture_config'});s=req({'action':'status'})
 ubus('service','set',{'name':'homepublish-p5-backend','instances':{'backend':{'command':['/usr/sbin/nginx','-p','/root/homepublish-p5/','-c','backend.conf'],'stdout':True,'stderr':True}}});started=True
 s=req({'action':'save','expected_revision':s['saved_revision'],'config':c})
 a=req({'action':'start','revision':s['saved_revision'],'approved':True});assert a['runtime']['phase']=='running',a
 assert marker()=='P5_PRODUCTION_A';passed('production IPv4 exact LAN -> IPv4 A; business systemCA hostname')
 c['services'][0]['backend']['port']=50883
 s=req({'action':'save','expected_revision':s['saved_revision'],'config':c});assert s['active_revision']!=s['saved_revision'] and marker()=='P5_PRODUCTION_A';passed('Save pending preserves A')
 b=req({'action':'apply','revision':s['saved_revision'],'approved':True});assert b['runtime']['phase']=='running' and b['runtime']['generation']!=a['runtime']['generation'] and marker()=='P5_PRODUCTION_B';passed('Apply new production procd generation B')
 assert req({'action':'stop'})['runtime']['cleanup']=='confirmed'
 c['access_profile']['listeners'][0].update(family='ipv6',address='fd89:878e:a47f::1',port=50884)
 s=req({'action':'save','expected_revision':s['saved_revision'],'config':c});a=req({'action':'start','revision':s['saved_revision'],'approved':True})
 assert a['runtime']['phase']=='running' and marker('fd89:878e:a47f::1',50884)=='P5_PRODUCTION_B';passed('second actual eligible IPv6 LAN -> IPv4 B')
 assert req({'action':'stop'})['runtime']['cleanup']=='confirmed';passed('owned production Stop confirmed')
 acl=json.loads(remote('cat /usr/share/rpcd/acl.d/luci-app-homepublish.json'))['luci-app-homepublish']
 reads=acl['read']['ubus']['homepublish'];writes=acl['write']['ubus']['homepublish']
 rd=ubus('session','create',{'timeout':120})['ubus_rpc_session'];sessions.append(rd)
 wr=ubus('session','create',{'timeout':120})['ubus_rpc_session'];sessions.append(wr)
 for sid,methods in [(rd,reads),(wr,reads+writes)]:ubus('session','grant',{'ubus_rpc_session':sid,'scope':'ubus','objects':[['homepublish',m] for m in methods]})
 for sid,label in [('0'*32,'anonymous'),(rd,'readonly')]:
  for method in writes:
   res=http(sid,method,{'revision':1,'approved':False} if method in ['start','apply'] else {})
   assert res.get('error',{}).get('code')==-32002,(label,method,res);passed(label+' denied '+method+' via actual HTTP rpcd')
 for method,args in [('status',{}),('network_inventory',{}),('validate',{'config':c}),('certificates',{})]:
  res=http(rd,method,args);assert res['result'][0]==0,(method,res);passed('readonly allowed '+method)
 for method,args,expected in [('start',{'revision':1,'approved':False},'approval required'),('apply',{'revision':1,'approved':False},'approval required'),('start',{'revision':0,'approved':True},'revision conflict')]:
  res=http(wr,method,args);assert res['result'][0]==0 and res['result'][1].get('error')==expected,res;passed('write allowed '+method+'; controller rejects '+expected)
finally:
 for sid in sessions:ubus('session','destroy',{'ubus_rpc_session':sid})
 if started:
  assert req({'action':'stop'})['runtime']['cleanup']=='confirmed'
  ubus('service','delete',{'name':'homepublish-p5-backend'})
 assert not ubus('service','list',{'name':'homepublish-runtime'})
 remote('test ! -e /tmp/homepublish-runtime')
 listeners=remote('netstat -lntp')
 for port in [50881,50882,50883,50884]:assert ':'+str(port)+' ' not in listeners
 remote(cert_cmd+' > /root/homepublish-p5/business-source.after; cmp /root/homepublish-p5/business-source.before /root/homepublish-p5/business-source.after')
 passed('business source certificate/key hashes and permissions preserved server-only; all owned test listeners absent')
 assert baseline==remote('sha256sum /etc/homepublish/product/state /etc/config/firewall /etc/config/dropbear /etc/config/uhttpd /etc/config/passwall2 /etc/resolv.conf /etc/hosts')
 passed('owned group/runtime absent; live journal and management/network configuration unchanged; temporary sessions destroyed')
 (E/'production-and-rpcd-final.log').write_text('\n'.join(log)+'\n',encoding='utf-8')
manifest={}
for n in ['product-system-provider.lua','product-daemon.lua','product-cli.lua']:
 p=ROOT/'homepublish/files/usr/share/homepublish'/n;d=hashlib.sha256(p.read_bytes()).hexdigest()
 assert remote('sha256sum /usr/share/homepublish/'+n).split()[0]==d;manifest[n]=d
(E/'production-final-source-sha256.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
print('P5_HTTPS_PRODUCTION_AND_REAL_RPCD_SCOPED_GREEN')
