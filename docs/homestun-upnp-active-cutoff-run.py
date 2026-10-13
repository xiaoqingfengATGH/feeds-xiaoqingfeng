import pathlib,subprocess,tarfile,io,hashlib,json,datetime,time,socket,ssl,threading,shlex,re,xml.etree.ElementTree as ET
repo=pathlib.Path('D:/DevPortal/homelede/feeds-xiaoqingfeng-homestun');docs=repo/'docs';out=docs/'artifacts/upnp-lease-private/active-cutoff';out.mkdir(parents=True,exist_ok=True)
scratch=pathlib.Path('C:/Users/xiaoq/AppData/Local/hermes/profiles/ta/cache/scratch')
ssh=['ssh','-F','/dev/null','-i','D:/DevPortal/CloudHosts/HomePri.key','-p','222','-o','BatchMode=yes','-o','ConnectTimeout=8','root@127.0.0.1']
b='/tmp/homestun-test/upnp-active';r=b+'/root';host='homestun-test.homelede.com';ttl=120
R={'generation':'homestun-upnp-'+datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%SZ'),'local_deadline_seconds':ttl,'requested_lease_seconds':300,'mode':'UPnP explicit mapping; no STUN','requests':[]}
R['marker']=R['generation']+'-'+hashlib.sha256(str(time.time_ns()).encode()).hexdigest()[:24];marker=R['marker'];proc=None;added=False;staged=False;hold=None;backendproc=None
summary=docs/'homestun-upnp-active-cutoff.json'
def save():summary.write_text(json.dumps(R,ensure_ascii=False,indent=2),encoding='utf8')
def call(cmd,data=None,timeout=20,check=True):
 p=subprocess.run(ssh+[cmd],input=data,stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=timeout)
 with (out/'ssh-log.txt').open('ab') as f:f.write((cmd+'\n').encode()+p.stdout+p.stderr+b'\n')
 if check and p.returncode:raise RuntimeError((cmd,p.returncode,p.stderr.decode(errors='replace')))
 return p.stdout.decode(errors='replace')
def soap(action,args):
 svc='urn:schemas-upnp-org:service:WANIPConnection:1';url='http://192.168.1.1:5351/ctl/IPConn'
 assert action in ['GetSpecificPortMappingEntry','AddPortMapping','DeletePortMapping']
 env=ET.Element('{http://schemas.xmlsoap.org/soap/envelope/}Envelope',{'{http://schemas.xmlsoap.org/soap/envelope/}encodingStyle':'http://schemas.xmlsoap.org/soap/encoding/'})
 e=ET.SubElement(ET.SubElement(env,'{http://schemas.xmlsoap.org/soap/envelope/}Body'),'{'+svc+'}'+action)
 for k,v in args.items():ET.SubElement(e,k).text=str(v)
 argv=['curl','-q','--proxy','','--noproxy','*','--interface','ifhost!br-lan!192.168.1.2','--proto','=http','--max-redirs','0','--connect-timeout','2','--max-time','4','--max-filesize','262144','-sS','-w','\nMETA:%{http_code}:%{remote_ip}:%{remote_port}\n','-H','Content-Type: text/xml; charset="utf-8"','-H',f'SOAPAction: "{svc}#{action}"','--data-binary','@-','--url',url]
 raw=call(' '.join(map(shlex.quote,argv)),ET.tostring(env,encoding='utf8',xml_declaration=True)).encode()
 m=re.search(rb'\nMETA:(\d+):([^:]+):(\d+)\n$',raw);assert m and m[2]==b'192.168.1.1' and m[3]==b'5351';body=raw[:m.start()]
 assert b'<!DOCTYPE' not in body.upper() and b'<!ENTITY' not in body.upper()
 root=ET.fromstring(body);d={x.tag.split('}')[-1]:x.text or '' for x in root.iter()}
 rec={'action':action,'at_monotonic':time.monotonic(),'http_status':int(m[1]),'fault':d.get('errorCode'),'fields':{k:v for k,v in d.items() if k.startswith('New')}};R['requests'].append(rec)
 (out/f'soap-{len(R["requests"]):02d}.xml').write_bytes(body);save();return rec
key={'NewRemoteHost':'','NewExternalPort':18444,'NewProtocol':'TCP'}
def query():return soap('GetSpecificPortMappingEntry',key)
def owned(q):
 f=q['fields'];return not q['fault'] and all(f.get(k)==v for k,v in {'NewInternalPort':'18444','NewInternalClient':'192.168.1.2','NewPortMappingDescription':R['generation'],'NewEnabled':'1'}.items())
def stop():
 if proc and proc.poll() is None:
  call(f'test ! -f {b}/controller.pid || {{ p=$(cat {b}/controller.pid); test \"$(readlink /proc/$p/exe)\" = {r}/usr/libexec/homestun-lease && kill -TERM \"$p\"; }}',check=False)
  proc.wait(timeout=140)
def delete_owned(q):
 if owned(q):
  R['delete']=soap('DeletePortMapping',key);R['after_delete']=query();R['precise_cleanup_verified']=R['after_delete']['fault']=='714'
 else:R['cleanup_not_owned_or_unknown']=q
SNAP='sha256sum /etc/config/firewall /etc/config/network /etc/config/passwall2; if test -e /etc/config/homestun; then sha256sum /etc/config/homestun; else echo HOMESTUN_CONFIG_ABSENT; fi; ip -4 rule; ip -4 route; netstat -lnt'
def structural(text):
 obj=json.loads(text);a=[]
 for x in obj['nftables']:
  if 'rule' in x:
   for e in x['rule'].get('expr',[]):
    if 'counter' in e:e['counter']={'packets':0,'bytes':0}
  if any(k in x for k in ['rule','chain','table']):a.append(x)
 return a
try:
 R['initial_mapping']=query();assert R['initial_mapping']['fault']=='714', 'Occupied candidate; no exposure'
 R['baseline']=call(SNAP);rules_before=call('nft -j list ruleset',timeout=30);route_before=call('ip rule; ip route show table all');config_before=call('sha256sum /etc/config/firewall /etc/config/network /etc/config/passwall2; if test -e /etc/config/homestun; then sha256sum /etc/config/homestun; else echo HOMESTUN_CONFIG_ABSENT; fi')
 assert not any(':'+str(p)+' ' in R['baseline'] for p in [18444,18443,18081])
 ipk=docs/'artifacts/homestun_0.1.0-r1_x86_64.ipk';assert hashlib.sha256(ipk.read_bytes()).hexdigest()=='84087e052d2cefacc7ac943ef9bc74000206379d80ca31b4de5f9c58d0ca4c22'
 with tarfile.open(ipk) as t:data=t.extractfile('./data.tar.gz').read()
 with tarfile.open(fileobj=io.BytesIO(data)) as t:lease=t.extractfile('./usr/libexec/homestun-lease').read()
 forward=(scratch/'homestun-upnp-forwarder').read_bytes();R['lease_sha256']=hashlib.sha256(lease).hexdigest();R['forwarder_sha256']=hashlib.sha256(forward).hexdigest();R['forwarder_source_sha256']=hashlib.sha256((scratch/'homestun-upnp-forwarder.c').read_bytes()).hexdigest();backend=(scratch/'homestun-active-backend').read_bytes();R['backend_sha256']=hashlib.sha256(backend).hexdigest();R['backend_source_sha256']=hashlib.sha256((docs/'homestun-upnp-active-backend.c').read_bytes()).hexdigest();R['backend_stream_seconds']=182;R['backend_independent_guard_seconds']=210;R['actual_nginx_version']=call('nginx -v 2>&1');R['actual_nginx_sha256']=call('sha256sum /usr/sbin/nginx')
 cfg=f'''worker_processes 1; pid /tmp/homestun-upnp/nginx.pid; error_log stderr;
events {{ worker_connections 32; }} http {{ access_log off; proxy_read_timeout 240s; proxy_send_timeout 240s; send_timeout 240s;

server {{ listen 127.0.0.1:18443 ssl default_server; server_name _; ssl_certificate /tmp/homestun-upnp/cert.pem; ssl_certificate_key /tmp/homestun-upnp/key.pem; return 444; }}
server {{ listen 127.0.0.1:18443 ssl; server_name {host}; ssl_certificate /tmp/homestun-upnp/cert.pem; ssl_certificate_key /tmp/homestun-upnp/key.pem; location / {{ proxy_pass http://127.0.0.1:18081; proxy_set_header Host {host}; proxy_http_version 1.1; proxy_buffering off; }} }} }}'''
 files={'backend':backend,'root/usr/libexec/homestun-lease':lease,'root/usr/bin/natmap':forward,'root/tmp/homestun-upnp/nginx.conf':cfg.encode()};buf=io.BytesIO()
 with tarfile.open(fileobj=buf,mode='w:gz') as t:
  for name,data in files.items():
   m=tarfile.TarInfo(name);m.size=len(data);m.mode=0o600 if name.endswith('.conf') else 0o700;t.addfile(m,io.BytesIO(data))
 call('test -d /tmp/homestun-test && test -z "$(ls -A /tmp/homestun-test)" && mkdir -m 700 '+b+' && tar xzf - -C '+b,buf.getvalue());staged=True
 setup=f'''set -eu
r={r}
mkdir -p "$r/bin" "$r/lib" "$r/usr/lib" "$r/usr/sbin" "$r/etc" "$r/dev" "$r/var/lib/nginx/fastcgi" "$r/var/lib/nginx/uwsgi" "$r/var/lib/nginx/scgi"
chmod 1777 "$r/tmp"; chmod 700 "$r/tmp/homestun-upnp"
cp /bin/busybox "$r/bin/"; ln -s busybox "$r/bin/sh"
cp /usr/sbin/nginx "$r/usr/sbin/"; cp /etc/passwd /etc/group /etc/resolv.conf "$r/etc/"
for p in /lib/*.so* /usr/lib/libpcre.so* /usr/lib/libjson-c.so* /usr/lib/libssl.so* /usr/lib/libcrypto.so* /usr/lib/libz.so*; do [ ! -e "$p" ] || cp -L "$p" "$r$p"; done
: > "$r/dev/null"
openssl req -x509 -newkey rsa:2048 -nodes -keyout "$r/tmp/homestun-upnp/key.pem" -out "$r/tmp/homestun-upnp/cert.pem" -subj /CN={host} -addext subjectAltName=DNS:{host} -days 1 >/dev/null 2>&1
chmod 600 "$r/tmp/homestun-upnp/"*.pem
sha256sum "$r/usr/bin/natmap" "$r/usr/libexec/homestun-lease"
'''
 R['stage_hashes']=call('sh -s',setup.encode());R['transfer_backend_hash']=call(f'sha256sum {b}/backend');assert R['backend_sha256'] in R['transfer_backend_hash'];R['transfer_nginx_hash']=call(f'sha256sum {r}/usr/sbin/nginx');assert R['actual_nginx_sha256'].split()[0]==R['transfer_nginx_hash'].split()[0];cert=out/'test-cert.pem';cert.write_text(call('cat '+r+'/tmp/homestun-upnp/cert.pem'))
 R['native_300_rejection']=call(f'chroot {r} /usr/libexec/homestun-lease /tmp/homestun-upnp 300 18444 18443 unused.invalid unused.invalid; echo REJECTION_EXIT=$?')
 assert 'REJECTION_EXIT=2' in R['native_300_rejection']
 backendlog=(out/'backend.txt').open('wb');backendproc=subprocess.Popen(ssh+[f'cd /; {b}/backend 18081 {marker} & p=$!; echo "$p" > {b}/backend.pid; wait "$p"'],stdout=backendlog,stderr=subprocess.STDOUT);time.sleep(1)
 start=time.monotonic();R['local_started_monotonic']=start
 engine=(out/'engine.txt').open('wb');cmd=f'cd /; read u rest < /proc/uptime; printf \"%s\\n\" \"$u\" > {b}/native-start-uptime; chroot {r} /usr/libexec/homestun-lease /tmp/homestun-upnp {ttl} 18444 18443 unused.invalid unused.invalid & p=$!; echo "$p" > {b}/controller.pid; wait "$p"'
 proc=subprocess.Popen(ssh+[cmd],stdout=engine,stderr=subprocess.STDOUT);time.sleep(2)
 R['local_preflight']=call(f'curl -q --noproxy "*" --cacert {r}/tmp/homestun-upnp/cert.pem --resolve {host}:18444:192.168.1.2 -sS --connect-timeout 2 --max-time 5 https://{host}:18444/',check=False)
 assert R['local_preflight']==marker and proc.poll() is None
 sync_before=time.monotonic();clock=call(f'cat {b}/native-start-uptime; cat /proc/uptime');sync_after=time.monotonic()
 native_uptime=float(clock.splitlines()[0]);current_uptime=float(clock.splitlines()[1].split()[0]);native_start_estimate=(sync_before+sync_after)/2-(current_uptime-native_uptime)
 R['native_start_correlation']={'target_uptime_start':native_uptime,'native_client_estimated_start':native_start_estimate,'uncertainty_seconds':(sync_after-sync_before)/2+.02,'ssh_start_delay_seconds':native_start_estimate-start}
 pre_before=time.monotonic();pre=call(f'curl -q --noproxy "*" --cacert {r}/tmp/homestun-upnp/cert.pem --resolve {host}:18444:192.168.1.2 -sS -N --connect-timeout 2 --max-time 11 https://{host}:18444/hold',timeout=15,check=False);pre_after=time.monotonic()
 lines=[x.split() for x in pre.splitlines() if x.startswith('tick ')]
 assert len(lines)>=6 and all(x[3]==marker for x in lines), ('Target TLS stream prerequisite failed',pre)
 times=[float(x[2]) for x in lines];assert times[-1]-times[0]>=9.9 and all(1.8<b-a<2.3 for a,b in zip(times,times[1:]))
 R['target_tls_stream_preflight']={'ticks':lines,'span_seconds':times[-1]-times[0],'wall_elapsed':pre_after-pre_before,'PASS':True}
 assert time.monotonic()-start<30, 'Setup consumed local native TTL budget; stop before Add'

 R['candidate_before_add']=query();assert R['candidate_before_add']['fault']=='714'
 args=dict(key,NewInternalPort=18444,NewInternalClient='192.168.1.2',NewEnabled=1,NewPortMappingDescription=R['generation'],NewLeaseDuration=300)
 add_start=time.monotonic();R['mapping_started_monotonic']=add_start;R['add_attempted']=True;R['add']=soap('AddPortMapping',args)
 if R['add']['fault']:raise RuntimeError('Add fault '+R['add']['fault']+'; no permanent retry')
 added=True;R['readback']=query()
 if not owned(R['readback']):raise RuntimeError('Add readback unknown/unowned; stop without unsafe deletion')
 duration=int(R['readback']['fields']['NewLeaseDuration']);R['accepted_lease_seconds']=duration
 if duration<=0:
  stop();delete_owned(query());added=False;raise RuntimeError('Gateway returned permanent lease; service closed and owned entry deleted')
 if duration>300:raise RuntimeError('Gateway lease exceeds authorization')
 args=['curl','-q','--noproxy','*','-4','--cacert',str(cert),'--resolve',f'{host}:18444:60.20.170.34','--connect-timeout','5','--max-time','10','-sS','-v',f'https://{host}:18444/']
 p=subprocess.run(args,stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=13);R['external_https']={'exit':p.returncode,'body':p.stdout.decode(errors='replace'),'stderr':p.stderr.decode(errors='replace'),'marker_matches':p.stdout.decode(errors='replace')==marker,'elapsed_local':time.monotonic()-start};save()
 if p.returncode==0 and R['external_https']['marker_matches']:
  context=ssl.create_default_context(cafile=str(cert));sock=context.wrap_socket(socket.create_connection(('60.20.170.34',18444),5),server_hostname=host);sock.settimeout(140);sock.sendall(f'GET /hold HTTP/1.1\r\nHost: {host}\r\nConnection: close\r\n\r\n'.encode())
  def holding():
   n=0;ticks=[];first_byte=None;buf=b'';headers=None
   try:
    while True:
     data=sock.recv(4096)
     if not data:break
     n+=len(data);now=time.monotonic()
     if first_byte is None:first_byte=now-native_start_estimate
     buf+=data
     if headers is None and b'\r\n\r\n' in buf:
      header,buf=buf.split(b'\r\n\r\n',1);headers=header.decode('ascii')
     while headers is not None and b'\n' in buf:
      line,buf=buf.split(b'\n',1)
      if line.startswith(b'tick '):
       x=line.decode('ascii').strip().split();assert x[3]==marker
       ticks.append({'number':int(x[1]),'source_monotonic':float(x[2]),'received_elapsed_native':time.monotonic()-native_start_estimate})
    outcome='EOF'
   except ssl.SSLEOFError:outcome='TLS abrupt EOF'
   except Exception as ex:outcome=repr(ex)
   finally:sock.close()
   R['held_connection']={'bytes':n,'headers':headers,'first_byte_elapsed_native':first_byte,'ticks':ticks,'outcome':outcome,'elapsed_native_to_eof':time.monotonic()-native_start_estimate}
  hold=threading.Thread(target=holding);hold.start()
 proc.wait(timeout=max(1,140-(time.monotonic()-start)));R['supervisor_exit']=proc.returncode;R['local_elapsed_to_exit']=time.monotonic()-start;engine.close()
 if hold:hold.join(timeout=8)
 h=R.get('held_connection',{});ticks=h.get('ticks',[]);gap=h.get('elapsed_native_to_eof',0)-ticks[-1]['received_elapsed_native'] if ticks else None
 gaps=[b['received_elapsed_native']-a['received_elapsed_native'] for a,b in zip(ticks,ticks[1:])]
 R['held_stream_assessment']={'tick_count':len(ticks),'last_tick_to_eof_seconds':gap,'receive_gaps_seconds':gaps,'EOF_native_seconds':h.get('elapsed_native_to_eof'),'PASS':bool(len(ticks)>=40 and gap is not None and 0<=gap<3.5 and all(1.5<x<2.7 for x in gaps) and h.get('outcome') in ['EOF','TLS abrupt EOF'] and 119.5<h.get('elapsed_native_to_eof',0)<122 and [t['number'] for t in ticks]==list(range(1,len(ticks)+1)))}
 R['backend_after_native_cutoff']=call(f'curl -q --noproxy "*" -sS -N --max-time 3 http://127.0.0.1:18081/hold',timeout=6,check=False);R['backend_still_streaming_after_native_cutoff']=bool(marker in R['backend_after_native_cutoff'] and 'tick ' in R['backend_after_native_cutoff']);save()
 p=subprocess.run(args,stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=13);R['post_deadline_new_connection']={'exit':p.returncode,'stderr':p.stderr.decode(errors='replace')};save()
 if backendproc and backendproc.poll() is None:
  R['backend_stop']=call(f'p=$(cat {b}/backend.pid); test "$(readlink /proc/$p/exe)" = {b}/backend && kill -TERM "$p"',check=False);backendproc.wait(timeout=8)
 backendlog.close()
 # Service already closed; bounded read-only lease observation, never renewed.
 while time.monotonic()<add_start+duration+30:
  q=query();R['last_lease_query']=q
  if q['fault']=='714':R['natural_expiry_verified']=True;R['expiry_observed_seconds']=time.monotonic()-add_start;added=False;break
  if not owned(q):raise RuntimeError('Lease observation changed ownership; do not delete')
  time.sleep(min(15,max(0,add_start+duration+30-time.monotonic())))
 if added:delete_owned(query());added=False;R['natural_expiry_verified']=False
 R['status']='PASS' if R['held_stream_assessment']['PASS'] and R['backend_still_streaming_after_native_cutoff'] and R['post_deadline_new_connection']['exit']!=0 and R.get('natural_expiry_verified') else 'FAIL'
except Exception as ex:R['status']='blocked';R['error']=repr(ex)
finally:
 try:
  stop()
  if backendproc and backendproc.poll() is None:
   call(f'p=$(cat {b}/backend.pid); test \"$(readlink /proc/$p/exe)\" = {b}/backend && kill -TERM \"$p\"',check=False);backendproc.wait(timeout=8)
  if added or (R.get('add_attempted') and R['status']=='blocked'):delete_owned(query())
  R['final_mapping']=query()
  if staged:
   R['cleanup_readback']=call(f'cd /; netstat -lnt; for p in /proc/[0-9]*; do for f in root exe cwd; do x=$(readlink "$p/$f" 2>/dev/null || :); case "$x" in {b}*) echo "RETAINED $p/$f $x";; esac; done; done; test ! -e {r}/tmp/homestun-upnp/runner.lock && echo NATIVE_SNAPSHOT_ABSENT',timeout=30)
   if 'RETAINED' not in R['cleanup_readback'] and call(f'mount | grep {b} || true').strip()=='' and not any(':'+str(p)+' ' in R['cleanup_readback'] for p in [18081,18443,18444]):
    R['fixture_cleanup']=call(f'test -f {b}/controller.pid && test -f {r}/tmp/homestun-upnp/nginx.conf && test -f {r}/usr/bin/natmap && rm -rf {b} && test ! -e {b} && echo FIXTURE_ABSENT');R['fixture_removed']=True
  R['final_baseline']=call(SNAP);R['persistent_config_unchanged']=config_before==call('sha256sum /etc/config/firewall /etc/config/network /etc/config/passwall2; if test -e /etc/config/homestun; then sha256sum /etc/config/homestun; else echo HOMESTUN_CONFIG_ABSENT; fi');R['routing_unchanged']=route_before==call('ip rule; ip route show table all');R['rules_structurally_unchanged']=structural(rules_before)==structural(call('nft -j list ruleset',timeout=30));R['management_retained']=all(':'+str(p)+' ' in R['final_baseline'] for p in [22,80,443])
 except Exception as ex:R['cleanup_error']=repr(ex)
 save();print(json.dumps({k:v for k,v in R.items() if k not in ['baseline','final_baseline','requests','cleanup_readback']},ensure_ascii=False,indent=2))
