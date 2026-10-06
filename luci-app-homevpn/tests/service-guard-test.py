#!/usr/bin/env python3
import os,pathlib,subprocess,sys,tempfile
root=pathlib.Path(sys.argv[1])
with tempfile.TemporaryDirectory(prefix='hv-guard-') as d:
 p=pathlib.Path(d);(p/'bin').mkdir();(p/'enabled').write_text('0')
 def exe(f,t):f.write_text('#!/bin/sh\n'+t);f.chmod(0o755)
 exe(p/'bin/uci',f'cat {p}/enabled\n')
 swan=p/'swanctl'
 original='''start_service() {
 procd_value=started
}
reload_service() {
 start_service
}
service_triggers() {
 procd_value=triggered
}
'''
 swan.write_text(original)
 ctl=(root/'usr/share/homevpn/service-control.sh').read_text().replace('/usr/share/homevpn/service-lock.sh',str(p/'lock-lib')).replace('/etc/init.d/swanctl',str(swan)).replace('/etc/init.d/.homevpn-swanctl.',str(p/'new.'))
 (p/'ctl').write_text(ctl);(p/'lock-lib').write_text((root/'usr/share/homevpn/service-lock.sh').read_text().replace('/var/lock/homevpn-service.lock',str(p/'lock')))
 env=dict(os.environ,PATH=str(p/'bin')+':'+os.environ['PATH'])
 def run(s):
  r=subprocess.run(['busybox','ash','-c','extra_command() { :; }; . '+str(p/'ctl')+'; '+s],text=True,capture_output=True,env=env);assert r.returncode==0,(r.stdout,r.stderr);return r
 run('hv_install_guard');first=swan.read_bytes();run('hv_install_guard');assert first==swan.read_bytes()
 for entry in ['start_service','reload_service','service_triggers']:
  run('. '+str(swan)+'; procd_value=none; '+entry+'; [ "$procd_value" = none ]')
 (p/'enabled').write_text('1')
 run('. '+str(swan)+'; procd_value=none; start_service; [ "$procd_value" = started ]')
 (p/'lock').mkdir();r=run('. '+str(swan)+'; procd_value=none; start_service && exit 1; [ "$procd_value" = none ]');(p/'lock').rmdir()
 swan.write_text('unsupported vendor init\n');run('hv_install_guard && exit 1; test "$(cat '+str(swan)+')" = "unsupported vendor init"')
 print('PASS guard: atomic/idempotent install, disabled start/reload/interface triggers, enabled procd shell state preserved, concurrent busy, unsupported vendor rejected')
