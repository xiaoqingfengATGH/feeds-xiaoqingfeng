import sys,json,shlex,subprocess
from p5_resume_support import *
def req(q):return json.loads(remote('lua /root/homepublish-p5/four-cli.lua',json.dumps(q).encode()))
def ubus(m,d):return remote('ubus call service '+m+' '+shlex.quote(json.dumps(d)))
log=[]
try:
 remote("umask 077; cp /root/homepublish-p5/resume-backup/live-state /root/homepublish-p5/resume-backup/live-unchanged-copy; lua -e \"package.path='/usr/share/homepublish/?.lua;'..package.path;local s=assert(require('device-integrations').certificate_source('acme:home_rsa','home.iwonderful.top'));local f=assert(io.open('/root/homepublish-p5/tls-backend.sh','w'));f:write('#!/bin/sh\\nexec /usr/bin/openssl s_server -quiet -accept 127.0.0.1:50886 -cert '..s.certificate..' -key '..s.key..'\\n');f:close()\"")
 instances={'web':{'command':['/usr/sbin/nginx','-p','/root/homepublish-p5/','-c','backend.conf']},'tls':{'command':['/bin/sh','/root/homepublish-p5/tls-backend.sh']},'ssh':{'command':['/usr/bin/socat','TCP-LISTEN:50887,bind=127.0.0.1,reuseaddr,fork','SYSTEM:printf "SSH-2.0-P5_Backend\\r\\n"; sleep 120']},'raw':{'command':['/usr/bin/socat','TCP-LISTEN:50888,bind=127.0.0.1,reuseaddr,fork','EXEC:/bin/cat']}}
 ubus('set',{'name':'homepublish-p5-backend','instances':instances})
 c=req({'action':'fixture_config'});s=req({'action':'status'});s=req({'action':'save','expected_revision':s['saved_revision'],'config':c})
 a=req({'action':'start','revision':s['saved_revision'],'approved':True});log.append(a);assert a['runtime']['phase']=='running',a['runtime']
 assert all(v['ready'] for v in a['runtime']['services'].values())
 assert remote("env -u CURL_CA_BUNDLE -u SSL_CERT_FILE -u SSL_CERT_DIR curl -q --noproxy '*' --fail --silent --max-time 4 --resolve home.iwonderful.top:50881:192.168.1.2 https://home.iwonderful.top:50881/")=='P5_PRODUCTION_A'
 log.append({'https_system_CA_hostname_marker':'P5_PRODUCTION_A'})
 # Target-side held raw and native SSH protocol sockets survive until Stop.
 remote("cat > /root/homepublish-p5/held.lua",b"local n=require('nixio');local sockets={};for _,p in ipairs({50885,50881}) do local s=assert(n.socket('inet','stream'));assert(s:connect('192.168.1.2',p));s:setopt('socket','rcvtimeo',30);if p==50885 then assert(s:send('P5_RAW_HELD')==11);assert(s:recv(11)=='P5_RAW_HELD') else s:send('SSH-2.0-Held\\r\\n');assert(s:recv(128):match('^SSH%-2%.0')) end;sockets[#sockets+1]=s end;local f=assert(io.open('/root/homepublish-p5/held.ready','w'));f:write('ready');f:close();for _,s in ipairs(sockets) do local v=s:recv(1);assert(v=='' or v==nil,'held connection not closed');s:close() end;print('RAW_SSH_HELD_STOP_EOF_GREEN')")
 remote('rm -f /root/homepublish-p5/held.ready')
 held=subprocess.Popen(SSH+['lua /root/homepublish-p5/held.lua'],stdout=subprocess.PIPE,stderr=subprocess.PIPE)
 remote('for i in 1 2 3 4 5; do test -e /root/homepublish-p5/held.ready && exit 0; sleep 1; done; exit 1')
 assert req({'action':'stop'})['runtime']['cleanup']=='confirmed'
 stdout,stderr=held.communicate(timeout=35);assert held.returncode==0,(stdout,stderr);log.append({'held_eof':stdout.decode()})
 print('FOUR_PROTOCOL_START_HTTPS_MARKER_RAW_SSH_EOF_GREEN')
finally:
 try:log.append(req({'action':'stop'}))
 finally:ubus('delete',{'name':'homepublish-p5-backend'});(E/'four-production-lifecycle-attempt.json').write_text(json.dumps(log,indent=2))
