"""P4 bounded negatives, executed by the installed lifecycle fixture owner."""
import copy, hashlib, json, subprocess, time

def exercise(g):
 ssh,request,c,E,REMOTE=(g[k] for k in ('ssh','request','c','E','REMOTE'))
 root=g['ROOT'];fixture=REMOTE+'/controller-fixture'
 helper=root/'homepublish/tests/device-tcp-p4-negative-cli.lua'
 subprocess.run(g['SCP']+[helper.resolve().as_posix(),'root@127.0.0.1:'+REMOTE+'/'],check=True,capture_output=True)
 assert ssh('sha256sum '+REMOTE+'/'+helper.name).stdout.split()[0]==hashlib.sha256(helper.read_bytes()).hexdigest()
 s=request({'action':'save','expected_revision':0,'config':c});assert s['saved_revision']==1
 for mode,code in [('addressgone','ADDRESS_UNAVAILABLE'),('zonegone','ZONE_AMBIGUOUS'),('readfail','NETWORK_UNAVAILABLE')]:
  r=ssh('lua '+REMOTE+'/'+helper.name+' '+mode,json.dumps({'action':'preflight','revision':1}))
  response=json.loads(r.stdout);(E/('task27-'+mode+'.json')).write_text(json.dumps(response,indent=2))
  assert not response['ready'] and any(x.get('error_code')==code for x in response['blockers']),response
  assert not response['endpoints'],response
  after=request({'action':'status'})
  assert after['saved_config']==s['saved_config'] and after['saved_revision']==1
  assert after['saved_config']['access_profile']['listeners'][0]['address'] not in ('::','0.0.0.0')
  rejected=json.loads(ssh('lua '+REMOTE+'/'+helper.name+' '+mode,json.dumps({'action':'start','revision':1,'approved':True})).stdout)
  (E/('task27-'+mode+'-start.json')).write_text(json.dumps(rejected,indent=2))
  expected_error={'addressgone':'Selected address is unavailable on this network','zonegone':'Selected network must map to exactly one firewall zone','readfail':'Network inventory unavailable or malformed'}[mode]
  assert rejected=={'error':expected_error},('inventory fault did not reject real controller Start',mode,rejected)
  assert request({'action':'status'})==after,'rejected inventory-fault Start mutated journal'
  assert not json.loads(ssh("ubus call service list '{\"name\":\"homepublish-p3-controller\"}'").stdout)
  print('PASS installed preflight + real controller Start controlled live-snapshot fault',mode,code,'no fallback/endpoints/journal config mutation')
 assert not json.loads(ssh("ubus call service list '{\"name\":\"homepublish-p3-controller\"}'").stdout)
 # Real competing listener on the second, independent socket. No port stealing.
 blocker={'name':'homepublish-p3-blocker','instances':{'blocker':{'command':[REMOTE+'/nginx-private','-p',fixture+'/','-c','blocker.conf'],'env':{'OPENSSL_CONF':'/dev/null'},'stdout':True,'stderr':True}}}
 ssh('cat > '+fixture+'/blocker.conf','daemon off; pid blocker.pid; error_log stderr error; events {} stream {server {listen [::1]:49550; return "";}}')
 ssh('ubus call service set '+repr(json.dumps(blocker)));ssh('sleep 1')
 before=json.loads(ssh("ubus call service list '{\"name\":\"homepublish-p3-blocker\"}'").stdout)
 assert before['homepublish-p3-blocker']['instances']['blocker']['running']
 failed=request({'action':'start','revision':1,'approved':True})
 (E/'task27-port-conflict.json').write_text(json.dumps(failed,indent=2))
 assert failed['runtime']['phase']=='blocked' and not failed['runtime'].get('active_verified'),failed
 assert failed['runtime']['cleanup']=='confirmed',failed
 assert not json.loads(ssh("ubus call service list '{\"name\":\"homepublish-p3-controller\"}'").stdout)
 assert ssh('test ! -e '+REMOTE+'/controller-runtime',check=False).returncode==0
 after=json.loads(ssh("ubus call service list '{\"name\":\"homepublish-p3-blocker\"}'").stdout)
 assert after['homepublish-p3-blocker']['instances']['blocker']['pid']==before['homepublish-p3-blocker']['instances']['blocker']['pid']
 print('PASS actual occupied second port blocks whole generation, cleanup confirmed, foreign listener retained')
 ssh('ubus call service delete '+repr(json.dumps({'name':'homepublish-p3-blocker'})));ssh('sleep 2')
 late=json.loads(ssh('lua '+REMOTE+'/'+helper.name+' late-addressgone',json.dumps({'action':'start','revision':1,'approved':True})).stdout)
 (E/'task27-running-addressgone.json').write_text(json.dumps(late,indent=2))
 assert late['before']['runtime']['phase']=='running',late
 assert late['after']['runtime']['phase']=='retry_wait' and not late['after']['runtime']['active_verified'],('running binding disappearance remained active',late)
 assert late['after']['runtime']['cleanup']=='confirmed',late
 assert not json.loads(ssh("ubus call service list '{\"name\":\"homepublish-p3-controller\"}'").stdout)
 assert ssh('test ! -e '+REMOTE+'/controller-runtime',check=False).returncode==0
 assert late['after']['saved_config']==s['saved_config'] and late['after']['active_config']==s['saved_config']
 assert all(l['address'] not in ('::','0.0.0.0') for l in late['after']['active_config']['access_profile']['listeners'])
 print('PASS running exact binding disappears at read-only inventory boundary: periodic renew stops whole group, cleanup confirmed, no wildcard fallback/config mutation')
 request({'action':'stop'})
 running=request({'action':'start','revision':1,'approved':True});assert running['runtime']['phase']=='running',running
 state=json.loads(ssh("ubus call service list '{\"name\":\"homepublish-p3-controller\"}'").stdout)
 pid=state['homepublish-p3-controller']['instances']['sslh']['pid']
 # Target nixio drives actual sockets; local Python never executes product logic.
 lua="""local n=require('nixio');local fs=n.fs
local pid=PID
local function resource()
 local count=0;for _ in fs.dir('/proc/'..pid..'/fd') do count=count+1 end
 local f=assert(io.open('/proc/'..pid..'/status'));local text=f:read('*a');f:close()
 return {fds=count,rss_kib=tonumber(text:match('VmRSS:%s+(%d+)'))}
end
local base=resource();local sockets={}
for i=1,24 do local s=assert(n.socket('inet6','stream'));assert(s:connect('::1',49543));s:setopt('socket','rcvtimeo',2);assert(s:send(string.char(22,3))==2);sockets[#sockets+1]=s end
local peak=resource()
assert(os.execute("env -u CURL_CA_BUNDLE -u SSL_CERT_FILE -u SSL_CERT_DIR curl -q --noproxy '*' --connect-timeout 2 --max-time 4 --fail --silent --output /dev/null --resolve 'home.iwonderful.top:49543:[::1]' https://home.iwonderful.top:49543/")==0,'legitimate request starved')
n.nanosleep(3)
for _,s in ipairs(sockets) do local data=s:recv(16);assert(data=='','slow handshake did not EOF');s:close() end
for _,payload in ipairs({'GARBAGE NOT A PROTOCOL\\r\\n','GET / HTTP/1.0\\r\\n\\r\\n'}) do
 local s=assert(n.socket('inet6','stream'));s:setopt('socket','rcvtimeo',3);assert(s:connect('::1',49543));s:send(payload);local d=s:recv(256);assert(d=='','unknown traffic returned business bytes or remained open');s:close()
end
n.nanosleep(1);local final=resource();assert(final.fds<=base.fds+2,'sslh descriptors retained');assert(peak.fds<=base.fds+32,'unexpected FD growth');assert(final.rss_kib<=base.rss_kib+2048,'bounded RSS growth exceeded')
print(require('luci.jsonc').stringify({base=base,peak=peak,final=final,slow_clients=24,slow_eof=24,unknown_eof=2,timeout_seconds=3,legitimate_during_load=true}))
""".replace('PID',str(pid))
 ssh('cat > '+fixture+'/bounded-negative.lua',lua)
 result=ssh('lua '+fixture+'/bounded-negative.lua');print(result.stdout.strip())
 (E/'task27-resource-observation.json').write_text(result.stdout)
 unknown=ssh("timeout 6 openssl s_client -connect '[::1]:49543' -servername unknown.fixture.home -quiet </dev/null",check=False)
 assert unknown.stdout=='' and unknown.returncode not in (0,124),'unknown SNI returned bytes, completed TLS or hung'
 assert 'unexpected eof' in unknown.stderr.lower(),'unknown SNI did not fail closed with actual EOF'
 (E/'task27-unknown-sni.txt').write_text('exit='+str(unknown.returncode)+'\n'+unknown.stdout+unknown.stderr)
 same=json.loads(ssh("ubus call service list '{\"name\":\"homepublish-p3-controller\"}'").stdout)
 assert same['homepublish-p3-controller']['instances']['sslh']['pid']==pid
 print('PASS actual 24 slow partial handshakes EOF, unknown plaintext/SNI rejected, healthy business request during load, bounded FD/RSS and unchanged procd PID')
 stopped=request({'action':'stop'});assert stopped['runtime']['cleanup']=='confirmed'
 assert not json.loads(ssh("ubus call service list '{\"name\":\"homepublish-p3-controller\"}'").stdout)
 (E/'task27-harness-sha256.json').write_text(json.dumps({p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in [helper,root/'homepublish/tests/p4_negative.py',root/'homepublish/tests/run-device-tcp-p4-lifecycle.py']},indent=2))
 print('P4_TASK26_27_BOUNDED_NEGATIVE_GREEN')
