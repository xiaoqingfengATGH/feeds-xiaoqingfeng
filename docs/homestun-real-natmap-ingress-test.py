import pathlib,subprocess,tarfile,io,hashlib,json,datetime,time,sys,socket,ssl,threading
repo=pathlib.Path('D:/DevPortal/homelede/feeds-xiaoqingfeng-homestun')
docs=repo/'docs'; b='/tmp/homestun-test/realnat-ingress'; r=b+'/root'; ttl=90
host='homestun-test.homelede.com'
ssh=['ssh','-F','/dev/null','-i','D:/DevPortal/CloudHosts/HomePri.key','-p','222','-o','BatchMode=yes','-o','ConnectTimeout=10','root@127.0.0.1']
log=docs/'homestun-real-natmap-ingress-log.txt'; result=docs/'homestun-real-natmap-ingress-result.json'
def now():return datetime.datetime.now(datetime.timezone.utc).isoformat()
def call(cmd,data=None,timeout=25,check=True):
 p=subprocess.run(ssh+[cmd],input=data,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=timeout)
 text=p.stdout.decode(errors='replace')
 with log.open('a',encoding='utf8') as f:f.write(now()+' $ '+cmd+'\n'+text+'\nexit='+str(p.returncode)+'\n')
 print(text,flush=True)
 if check and p.returncode:raise RuntimeError((cmd,p.returncode,text))
 return text
if sys.argv[1]=='stage':
 generation='realnat-'+datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%SZ')
 marker=generation+'-'+hashlib.sha256(str(time.time_ns()).encode()).hexdigest()[:24]
 ipk=repo/'docs/artifacts/homestun_0.1.0-r1_x86_64.ipk'
 assert hashlib.sha256(ipk.read_bytes()).hexdigest()=='84087e052d2cefacc7ac943ef9bc74000206379d80ca31b4de5f9c58d0ca4c22'
 with tarfile.open(ipk) as t: data=t.extractfile('./data.tar.gz').read()
 with tarfile.open(fileobj=io.BytesIO(data)) as t:lease=t.extractfile('./usr/libexec/homestun-lease').read()
 natmap=(docs/'artifacts/natmap-20260214-sdk').read_bytes()
 assert hashlib.sha256(natmap).hexdigest()=='ba2df4ead5562b0bc0359881ffce1a07d65f62403b6e0b7e0980731be09c45b1'
 cfg=f'''worker_processes 1;
pid /tmp/homestun-real/nginx.pid;
error_log stderr;
events {{ worker_connections 32; }}
http {{ access_log /tmp/access.log; server {{ listen 127.0.0.1:18081; server_name {host}; location / {{ return 200 '{marker}'; }} location /hold {{ limit_rate 1; return 200 '{marker*8}'; }} }}
server {{ listen 127.0.0.1:18443 ssl default_server; server_name _; ssl_certificate /tmp/homestun-real/cert.pem; ssl_certificate_key /tmp/homestun-real/key.pem; return 444; }}
server {{ listen 127.0.0.1:18443 ssl; server_name {host}; ssl_certificate /tmp/homestun-real/cert.pem; ssl_certificate_key /tmp/homestun-real/key.pem; location / {{ proxy_pass http://127.0.0.1:18081; proxy_set_header Host {host}; proxy_buffering off; }} }} }}
'''
 wrapper=b'#!/bin/sh\nprintf "%s\\n" "$$" > /tmp/natmap.pid\nexec /usr/bin/natmap-real "$@" -i 192.168.1.2 -f 0xff -e /usr/bin/mapped-callback\n'
 callback=b'#!/bin/sh\nprintf "%s %s %s %s %s %s\\n" "$1" "$2" "$3" "$4" "$5" "$6" >> /tmp/mappings\n'
 files={'root/usr/libexec/homestun-lease':lease,'root/usr/bin/natmap-real':natmap,'capture':(docs/'artifacts/homestun-ingress-header-cap-sdk').read_bytes(),'root/usr/bin/natmap':wrapper,'root/usr/bin/mapped-callback':callback,'root/tmp/homestun-real/nginx.conf':cfg.encode()}
 buf=io.BytesIO()
 with tarfile.open(fileobj=buf,mode='w:gz') as t:
  for name,data in files.items():
   m=tarfile.TarInfo(name);m.size=len(data);m.mode=0o600 if name.endswith('.conf') else 0o700;t.addfile(m,io.BytesIO(data))
 call('test ! -e /tmp/homestun-test && mkdir -m 700 /tmp/homestun-test && mkdir -m 700 '+b+' && tar xzf - -C '+b,buf.getvalue())
 setup=f'''set -eu
r={r}
mkdir -p "$r/bin" "$r/lib" "$r/usr/lib" "$r/usr/sbin" "$r/etc" "$r/dev" "$r/var/lib/nginx/fastcgi" "$r/var/lib/nginx/uwsgi" "$r/var/lib/nginx/scgi"
chmod 1777 "$r/tmp"; chmod 700 "$r/tmp/homestun-real"
cp /bin/busybox "$r/bin/"; ln -s busybox "$r/bin/sh"
cp /usr/sbin/nginx "$r/usr/sbin/"; cp /etc/passwd /etc/group /etc/resolv.conf "$r/etc/"
for p in /lib/*.so* /usr/lib/libpcre.so* /usr/lib/libjson-c.so* /usr/lib/libssl.so* /usr/lib/libcrypto.so* /usr/lib/libz.so*; do [ ! -e "$p" ] || cp -L "$p" "$r$p"; done
: > "$r/dev/null"
openssl req -x509 -newkey rsa:2048 -nodes -keyout "$r/tmp/homestun-real/key.pem" -out "$r/tmp/homestun-real/cert.pem" -subj /CN={host} -addext subjectAltName=DNS:{host} -days 1 >/dev/null 2>&1
chmod 600 "$r/tmp/homestun-real/"*.pem
chroot "$r" /usr/bin/natmap-real --help 2>&1 || :
sha256sum "$r/usr/bin/natmap-real" "$r/usr/libexec/homestun-lease"
'''
 call('sh -s',setup.encode())
 cert=call('cat '+r+'/tmp/homestun-real/cert.pem')
 (docs/'artifacts/realnat-ingress-test-cert.pem').write_text(cert)
 state={'generation':generation,'marker':marker,'host':host,'ttl_seconds':ttl,'staged_at':now(),'stage':'ready; no lease started','bypass_method':'upstream -f 0xff SO_MARK for owned base/STUN/listener sockets only; no nft or route edits','natmap_revision':'f8d7996710677c9885c148dda80a42d626f0a17b','natmap_sha256':hashlib.sha256(natmap).hexdigest(),'lease_sha256':hashlib.sha256(lease).hexdigest()}
 result.write_text(json.dumps(state,indent=2)); print(json.dumps(state,indent=2)); sys.exit()
state=json.loads(result.read_text()); marker=state['marker']; proc=None; hold=None
try:
 state['rules_before']=call('nft -j list ruleset',timeout=30); state['routing_before']=call('ip rule; ip route show table all; ip route get 1.1.1.1 mark 255'); state['uci_before']=call('sha256sum /etc/config/firewall /etc/config/passwall2')
 state['pre_capture_routes']=call('ip route get 61.148.12.162; ip route get 61.148.12.162 mark 255; cat /proc/sys/net/ipv4/conf/all/rp_filter /proc/sys/net/ipv4/conf/br-lan/rp_filter; nft list chain inet fw4 input; nft list chain inet fw4 input_lan; nft list chain inet fw4 accept_from_lan; nft list chain inet fw4 syn_flood; nft list chain inet fw4 handle_reject; ip neigh show 192.168.1.1')
 state['started_at']=now(); start=time.monotonic()
 capture_files=[];capture_processes=[]
 for iface,peer,label in [('br-lan','61.148.12.162','external'),('br-lan','192.168.1.2','local-br'),('lo','192.168.1.2','local-lo')]:
  f=(docs/('homestun-real-natmap-ingress-capture-'+label+'.txt')).open('wb');capture_files.append(f)
  cp=subprocess.Popen(ssh+[f'{b}/capture {iface} {peer} 90'],stdout=f,stderr=subprocess.STDOUT);capture_processes.append(cp)
 time.sleep(1)
 cmd=f'cd /; chroot {r} /usr/libexec/homestun-lease /tmp/homestun-real {ttl} 18444 18443 turn.cloudflare.com example.com & p=$!; echo "$p" > {b}/controller.pid; wait "$p"'
 outfile=(docs/'homestun-real-natmap-ingress-engine.txt').open('wb')
 proc=subprocess.Popen(ssh+[cmd],stdout=outfile,stderr=subprocess.STDOUT)
 state['stage']='lease active';result.write_text(json.dumps(state,indent=2))
 time.sleep(2)
 state['native_state']=call(f'p=$(cat {r}/tmp/natmap.pid); cat /proc/$p/status; netstat -lnt; curl -q --noproxy "*" --cacert {r}/tmp/homestun-real/cert.pem --resolve {host}:18443:127.0.0.1 -sS --max-time 5 https://{host}:18443/',check=False)
 endpoint=None
 while time.monotonic()-start<ttl-15 and proc.poll() is None:
  text=call(f'test ! -f {r}/tmp/mappings || cat {r}/tmp/mappings',check=False)
  if text.strip():
   fields=text.strip().splitlines()[-1].split()
   if len(fields)==6 and fields[4]=='tcp':
    socket.inet_aton(fields[0]); port=int(fields[1]);assert 0<port<65536
    endpoint=(fields[0],port);state['callback_fields']=fields;break
  time.sleep(3)
 state['mapping_observed_at']=now() if endpoint else None
 state['public_endpoint']=f'{endpoint[0]}:{endpoint[1]}' if endpoint else None
 if endpoint:
  state['local_forwarding']=call(f'curl -q --noproxy "*" --cacert {r}/tmp/homestun-real/cert.pem --resolve {host}:18444:192.168.1.2 -sS --connect-timeout 3 --max-time 5 https://{host}:18444/',check=False)
  state['local_marker_matches']=state['local_forwarding'].strip()==marker
  state['bypass_counters_live']=call('nft list chain inet passwall2 PSW2_OUTPUT_NAT; nft list chain inet passwall2 PSW2_OUTPUT_MANGLE')
  try:
   tcp=socket.create_connection(endpoint,timeout=5); state['external_tcp']={'connected':True,'local':tcp.getsockname(),'peer':tcp.getpeername(),'at':now()};tcp.close()
  except Exception as e:state['external_tcp']={'connected':False,'error':repr(e),'at':now()}
  state['external_probe_public_ip']='61.148.12.162; independently observed Windows direct curl before lease'
  url=f'https://{host}:{endpoint[1]}/'
  args=['curl','-q','--noproxy','*','-4','--cacert',str(docs/'artifacts/realnat-ingress-test-cert.pem'),'--resolve',f'{host}:{endpoint[1]}:{endpoint[0]}','--connect-timeout','5','--max-time','10','-sS','-v',url]
  cp=subprocess.run(args,stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=13)
  state['external_curl']={'exit':cp.returncode,'body':cp.stdout.decode(errors='replace'),'stderr':cp.stderr.decode(errors='replace'),'marker_matches':cp.stdout.decode(errors='replace')==marker,'at':now()}
  if cp.returncode==0 and state['external_curl']['marker_matches']:
   context=ssl.create_default_context(cafile=str(docs/'artifacts/realnat-ingress-test-cert.pem'))
   sock=context.wrap_socket(socket.create_connection(endpoint,timeout=5),server_hostname=host);sock.settimeout(ttl+20)
   sock.sendall(f'GET /hold HTTP/1.1\r\nHost: {host}\r\nConnection: close\r\n\r\n'.encode())
   def read_hold():
    total=0;beg=time.monotonic()
    try:
     while True:
      chunk=sock.recv(4096)
      if not chunk:break
      total+=len(chunk)
     state['held_connection']={'bytes':total,'outcome':'EOF','seconds_since_lease_start':time.monotonic()-start,'elapsed_seconds':time.monotonic()-beg}
    except Exception as e:state['held_connection']={'bytes':total,'outcome':repr(e),'seconds_since_lease_start':time.monotonic()-start,'elapsed_seconds':time.monotonic()-beg}
    finally:sock.close()
   hold=threading.Thread(target=read_hold);hold.start()
 else:state['external_curl']={'status':'not attempted; no real STUN callback'}
 proc.wait(timeout=max(1,ttl+12-(time.monotonic()-start)));outfile.close()
 state['supervisor_exit']=proc.returncode;state['elapsed_to_exit']=time.monotonic()-start;state['expired_at']=now()
 if hold:hold.join(timeout=8)
 if endpoint:
  cp=subprocess.run(args,stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=13)
  state['post_expiry_new_connection']={'exit':cp.returncode,'body':cp.stdout.decode(errors='replace'),'stderr':cp.stderr.decode(errors='replace'),'at':now()}
except Exception as e:
 state['error']=repr(e)
finally:
 if proc and proc.poll() is None:
  call(f'test ! -f {b}/controller.pid || kill -TERM $(cat {b}/controller.pid)',check=False)
  try:proc.wait(timeout=ttl+12)
  except Exception as e:state['wait_error']=repr(e)
 time.sleep(1)
 for cp in locals().get('capture_processes',[]):
  try:cp.wait(timeout=8)
  except subprocess.TimeoutExpired:
   cp.terminate();cp.wait(timeout=5)
 for f in locals().get('capture_files',[]):f.close()
 state['capture_text']={label:(docs/('homestun-real-natmap-ingress-capture-'+label+'.txt')).read_text() for label in ['external','local-br','local-lo']}
 state['cleanup_readback']=call(f'cd /; netstat -lnt; nft list ruleset | sha256sum; for p in /proc/[0-9]*; do for f in root exe cwd; do x=$(readlink "$p/$f" 2>/dev/null || :); case "$x" in {b}*) echo "RETAINED $p/$f $x";; esac; done; done; ls {r}/tmp/homestun-real; test ! -e {r}/tmp/homestun-real/runner.lock && echo NATIVE_SNAPSHOT_ABSENT',timeout=30,check=False)
 state['rules_after']=call('nft -j list ruleset',timeout=30); state['routing_after']=call('ip rule; ip route show table all; ip route get 1.1.1.1 mark 255'); state['uci_after']=call('sha256sum /etc/config/firewall /etc/config/passwall2')
 def structural(text):
  obj=json.loads(text); out=[]
  for item in obj['nftables']:
   if 'metainfo' in item:continue
   if 'rule' in item:
    for ex in item['rule'].get('expr',[]):
     if 'counter' in ex:ex['counter']={'packets':0,'bytes':0}
    out.append(item)
   elif 'chain' in item or 'table' in item:out.append(item)
  return out
 state['rules_structurally_unchanged']=structural(state['rules_before'])==structural(state['rules_after'])
 state['routing_unchanged']=state['routing_before']==state['routing_after']
 state['persistent_config_unchanged']=state['uci_before']==state['uci_after']
 if 'RETAINED' not in state['cleanup_readback'] and not any(':'+str(p)+' ' in state['cleanup_readback'] for p in [18443,18444,18081]):
  call('rm -rf '+b+'; rmdir /tmp/homestun-test; test ! -e '+b+' && echo FIXTURE_ABSENT')
  state['fixture_removed']=True
 else:state['fixture_removed']=False
 state['final_at']=now();state['stage']='finished';result.write_text(json.dumps(state,indent=2));print(json.dumps(state,indent=2))
