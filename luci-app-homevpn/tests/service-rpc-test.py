#!/usr/bin/env python3
"""Real rpcd shell/jshn, isolated UCI and init-service boundary only."""
import json,os,pathlib,subprocess,sys,tempfile
src=pathlib.Path(sys.argv[1]).read_text(); jshn=sys.argv[2]
with tempfile.TemporaryDirectory(prefix='hv-toggle-rpc-') as d:
 p=pathlib.Path(d); (p/'bin').mkdir(); log=p/'calls';state=p/'enabled';state.write_text('1')
 def exe(path,text): path.write_text('#!/bin/sh\n'+text);path.chmod(0o755)
 exe(p/'bin/uci',f'[ "$1" = -q ] && shift\ncase "$1:$2" in get:homevpn.config.enabled) cat "{state}";; *) exit 1;; esac\n')
 exe(p/'init',f'printf "%s\\n" "$*" >> "{log}"\n[ -f "{p}/fail" ] && {{ echo "service failed"; exit 1; }}\n[ "$1" = set-enabled ] || exit 2\nprintf "%s" "$2" > "{state}"\n')
 (p/'resolver').write_text(':\n')
 src=src.replace('/usr/share/libubox/jshn.sh',jshn).replace('/usr/share/homevpn/acme-resolve.sh',str(p/'resolver')).replace('/etc/init.d/homevpn',str(p/'init'))
 (p/'lock-lib').write_text((pathlib.Path(sys.argv[1]).parents[2]/'share/homevpn/service-lock.sh').read_text().replace('/var/lock/homevpn-service.lock',str(p/'lock')))
 src=src.replace('/usr/share/homevpn/service-lock.sh',str(p/'lock-lib'))
 src=src.replace('/usr/share/homevpn/selfsigned-pki.sh',str(pathlib.Path(sys.argv[1]).parents[2]/'share/homevpn/selfsigned-pki.sh'))
 rpc=p/'rpc';rpc.write_text(src)
 env=dict(os.environ,PATH=str(p/'bin')+':'+os.environ['PATH'])
 def call(arg):
  r=subprocess.run(['busybox','ash',str(rpc),'call','set_enabled'],input=json.dumps(arg)+'\n',text=True,capture_output=True,env=env);assert r.returncode==0,r.stderr;return json.loads(r.stdout)
 r=call({'enabled':False,'pool_subnet':'bad','cert_mode':'acme'});assert r.get('ok') is True,r
 assert state.read_text()=='0';assert log.read_text().splitlines()==['set-enabled 0']
 for x in [{},{'enabled':None},{'enabled':0},{'enabled':1},{'enabled':'false'},{'enabled':[]},{'enabled':{}}]:
  assert call(x)['ok'] is False,x
 assert len(log.read_text().splitlines())==1
 assert call({'enabled':True})['ok'] is True;assert state.read_text()=='1'
 (p/'fail').touch();r=call({'enabled':False});assert r['ok'] is False and 'failed' in r['error'],r;assert state.read_text()=='1'
 print('PASS actual rpcd/jshn: strict boolean, independent toggle, invalid CIDR/ACME irrelevant, exit failure surfaced')
