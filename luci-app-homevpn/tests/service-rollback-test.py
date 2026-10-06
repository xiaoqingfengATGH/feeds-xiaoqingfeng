#!/usr/bin/env python3
"""Exercise actual controller/cleanup; record network boundary state and faults."""
import os,pathlib,subprocess,sys,tempfile
root=pathlib.Path(sys.argv[1])
with tempfile.TemporaryDirectory(prefix='hv-rollback-') as d:
 p=pathlib.Path(d);(p/'bin').mkdir()
 def exe(name,text):
  f=p/name;f.write_text('#!/bin/sh\n'+text);f.chmod(0o755)
 exe('bin/uci',f'''[ "$1" != -q ] || shift
 echo "uci $*" >> {p}/calls
 case "$1" in
 set) echo "${{2##*=}}" > {p}/enabled;;
 get) cat {p}/enabled;;
 commit) [ ! -f {p}/commit-fail ];;
 delete) rm -f {p}/firewall;;
 esac
 ''')
 exe('swan',f'''echo "swan $1" >> {p}/calls
 case "$1" in
 disable) [ ! -f {p}/disable-fail ];;
 stop) [ ! -f {p}/stop-fail ] || exit 1; rm -f {p}/running;;
 esac
 ''')
 exe('firewall-init',f'echo firewall-reload >> {p}/calls\n[ ! -f {p}/reload-fail ]\n')
 exe('home',':\n')
 exe('bin/ip',f'''echo "ip $*" >> {p}/calls
 case "$2" in
 show) [ ! -e {p}/route ] || echo '10.99.0.0/24 dev lo';;
 del) rm -f {p}/route;;
 esac
 ''')
 text=(root/'usr/share/homevpn/service-control.sh').read_text()
 for a,b in [('/usr/share/homevpn/service-lock.sh',str(p/'lock')),('/etc/init.d/swanctl',str(p/'swan')),('/etc/init.d/homevpn',str(p/'home')),('/etc/init.d/firewall',str(p/'firewall-init'))]:text=text.replace(a,b)
 (p/'control').write_text(text);(p/'lock').write_text((root/'usr/share/homevpn/service-lock.sh').read_text().replace('/var/lock/homevpn-service.lock',str(p/'service.lock')))
 (p/'driver').write_text(f'''extra_command() {{ :; }}
 . {p}/control
 hv_exclusive() {{ :; }}
 hv_install_guard() {{ :; }}
 hv_get() {{ cat {p}/enabled; }}
 hv_ready() {{ return 1; }}
 pidof() {{ [ -f {p}/running ]; }}
 load_env() {{ LAN_ADDR=192.0.2.1; MODE=subnet; POOL_SUBNET=10.99.0.0/24; }}
 precheck() {{ :; }}
 provision_certs() {{ :; }}
 state_get() {{ [ -f {p}/state-present ] || return 0; case "$1" in mode) echo subnet;; pool) echo 10.99.0.0/24;; esac; }}
 drop_client_include() {{ echo include-clean >> {p}/calls; }}
 ensure_firewall() {{ touch {p}/firewall; }}
 apply_config() {{ touch {p}/route; return 1; }}
 hv_set_enabled "$1"
 ''')
 env=dict(os.environ,PATH=str(p/'bin')+':'+os.environ['PATH'])
 def run(wanted):return subprocess.run(['busybox','ash',str(p/'driver'),wanted],env=env,text=True,capture_output=True)
 (p/'enabled').write_text('0')
 result=run('1');assert result.returncode!=0
 assert not (p/'firewall').exists(),'failed enable leaves new firewall'
 assert not (p/'route').exists(),'failed enable leaves new route before state was written'
 assert (p/'enabled').read_text().strip()=='0'
 for failure in ['commit','disable','stop','reload']:
  (p/'state-present').touch();(p/'route').touch()
  (p/'calls').write_text('');(p/'enabled').write_text('1');(p/'running').touch();(p/(failure+'-fail')).touch()
  result=run('0');assert result.returncode!=0,(failure,result.stderr)
  calls=(p/'calls').read_text()
  for step in ['swan disable','swan stop','include-clean','firewall-reload']:assert step in calls,(failure,step,calls)
  assert not (p/'route').exists(),(failure,'network cleanup stopped before route removal')
  assert result.stderr,(failure,'must report residual/failure')
  (p/(failure+'-fail')).unlink();(p/'running').unlink(missing_ok=True)
 print('PASS rollback removes new firewall/route with absent state; commit/disable/stop/reload failures all attempt safety steps and report errors')
