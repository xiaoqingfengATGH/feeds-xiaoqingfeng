#!/usr/bin/env python3
"""Actual init/control functions in target ash; isolated service/uci boundary."""
import os,pathlib,subprocess,sys,tempfile
root=pathlib.Path(sys.argv[1]); ash=['busybox','ash']
with tempfile.TemporaryDirectory(prefix='hv-service-') as d:
 p=pathlib.Path(d);(p/'conf.d').mkdir();(p/'bin').mkdir();(p/'enabled').write_text('1');(p/'running').touch()
 def exe(path,s):path.write_text('#!/bin/sh\n'+s);path.chmod(0o755)
 exe(p/'bin/uci',f'''[ "$1" = -q ] && shift
case "$1" in
get) case "$2" in homevpn.config.enabled) cat {p}/enabled;; homevpn.config) echo homevpn;; *) exit 1;; esac;;
set) printf '%s' "${{2##*=}}" > {p}/enabled;;
commit) :;; show) :;; esac
''')
 exe(p/'bin/pidof',f'[ -e {p}/running ] && echo 4242\n')
 exe(p/'bin/swanctl',f'''case "$1" in
--list-conns|--list-conn) [ -e {p}/running ] || exit 1; echo 'homevpn-eap: IKEv2'; [ ! -e {p}/foreign ] || echo 'other: IKEv2';;
--load-all) [ ! -e {p}/load-fail ];;
*) :;; esac
''')
 exe(p/'swanctl',f'''echo "$1" >> {p}/service-calls
case "$1" in stop) rm -f {p}/running;; start|restart) [ ! -e {p}/start-fail ] || exit 1; touch {p}/running;; disable) [ ! -e {p}/disable-fail ] || exit 1; rm -f {p}/swan-boot;; enable) touch {p}/swan-boot;; esac
''')
 exe(p/'homevpn',f'[ "$1" != enable ] || touch {p}/home-boot\n')
 control=root/'usr/share/homevpn/service-control.sh';(p/'main.conf').write_text('include conf.d/*.conf\ninclude /var/swanctl/swanctl.conf\n')
 src=(root/'etc/init.d/homevpn').read_text()
 if control.exists():
  (p/'control').write_text(control.read_text().replace('/usr/share/homevpn/service-lock.sh',str(p/'lock-lib')))
  (p/'lock-lib').write_text((root/'usr/share/homevpn/service-lock.sh').read_text().replace('/var/lock/homevpn-service.lock',str(p/'lock')))
 src=src.replace('/usr/share/homevpn/service-control.sh',str(p/'control'))
 # Only absolute environment paths, never implementation logic, are adapted.
 for a,b in [('/etc/init.d/swanctl',str(p/'swanctl')),('/etc/init.d/homevpn',str(p/'homevpn')),('/var/lock/homevpn-service.lock',str(p/'lock')),('/var/swanctl/swanctl.conf',str(p/'var.conf')),('/etc/swanctl',str(p)),('/etc/config/homevpn',str(p/'enabled'))]:
  src=src.replace(a,b)
  if (p/'control').exists(): (p/'control').write_text((p/'control').read_text().replace(a,b))
 if (p/'control').exists():
  c=(p/'control').read_text().replace(str(p)+'/swanctl.conf',str(p/'main.conf'));(p/'control').write_text(c)
 (p/'main.conf').write_text('include conf.d/*.conf\ninclude '+str(p/'var.conf')+'\n')
 src=src.replace('/usr/share/homevpn/selfsigned-pki.sh',str(root/'usr/share/homevpn/selfsigned-pki.sh'))
 (p/'init').write_text(src)
 script=f'''extra_command() {{ :; }}
. {p}/init
logger_tag() {{ :; }}
# Rendering is unrelated to lifecycle and must not touch host networking/PKI.
load_env() {{ LAN_ADDR=192.0.2.1; }}
precheck() {{ [ ! -f {p}/precheck-fail ]; }}
provision_certs() {{ [ ! -f {p}/cert-fail ]; }}
ensure_firewall() {{ :; }}
regen_secrets() {{ :; }}
render_plugin_conf() {{ PLUGIN_RESTART=0; }}
render_user_bindings() {{ :; }}
render_conf() {{ :; }}
apply_include() {{ :; }}
apply_client_rules() {{ :; }}
apply_subnet_routes() {{ :; }}
hv_state() {{ :; }}
hv_cleanup_network() {{ :; }}
"$@"
'''
 (p/'driver').write_text(script);env=dict(os.environ,PATH=str(p/'bin')+':'+os.environ['PATH'])
 def run(*args,ok=True):
  r=subprocess.run(ash+[str(p/'driver'),*args],text=True,capture_output=True,env=env)
  assert (r.returncode==0)==ok,(args,r.returncode,r.stdout,r.stderr)
  return r
 # guard installation is separately tested; this fixture exercises the controller.
 (p/'swanctl').write_text((p/'swanctl').read_text()+'\n# homevpn-service-guard-v2\n')
 (p/'disable-fail').touch();run('set-enabled','0',ok=False);assert not (p/'running').exists(),'disable failure must still stop charon';(p/'disable-fail').unlink()
 run('set-enabled','1')
 run('set-enabled','0');assert not (p/'running').exists();assert (p/'enabled').read_text()=='0'
 for cmd in ['regen','reload_service','boot','sync-acme','provision','start_service']:
  run(cmd);assert not (p/'running').exists(),cmd
 run('set-enabled','0');assert not (p/'running').exists()
 run('set-enabled','1');assert (p/'running').exists();assert (p/'home-boot').exists()
 before=(p/'service-calls').read_text();run('set-enabled','1');assert (p/'service-calls').read_text()==before,'repeated enable restarts service'
 (p/'foreign').touch();run('set-enabled','0',ok=False);assert (p/'running').exists() and (p/'enabled').read_text()=='1';(p/'foreign').unlink()
 (p/'conf.d/other.conf').write_text('connections { other {} }');run('set-enabled','0',ok=False);assert (p/'running').exists();(p/'conf.d/other.conf').unlink()
 run('set-enabled','0');(p/'precheck-fail').touch();run('set-enabled','1',ok=False);assert not (p/'running').exists();assert (p/'enabled').read_text()=='0';(p/'precheck-fail').unlink()
 (p/'start-fail').touch();run('set-enabled','1',ok=False);assert not (p/'running').exists() and (p/'enabled').read_text()=='0';(p/'start-fail').unlink()
 run('set-enabled','0')
 for content in ['connections { foreign {} }', 'include /elsewhere/*.conf']:
  (p/'var.conf').write_text(content);run('set-enabled','1',ok=False);assert not (p/'running').exists();assert (p/'enabled').read_text()=='0';(p/'var.conf').unlink()
 for content in ['include /elsewhere/*.conf', 'connections { homevpn-eap { include /elsewhere/*.conf } }']:
  (p/'conf.d/homevpn.conf').write_text(content);run('set-enabled','1',ok=False);assert not (p/'running').exists();(p/'conf.d/homevpn.conf').unlink()
 (p/'lock').mkdir();run('set-enabled','1',ok=False);assert not (p/'running').exists();(p/'lock').rmdir()
 print('PASS actual ash init: off stops supervisor, persistent entry gates, on, repeat, foreign live/disk config refusal, precheck/start failure rollback, busy')
