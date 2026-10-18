"""Read-only post-deployment Host/NAT checks; accepts native nginx 400 rejection."""
import hashlib,json,pathlib,runpy,shlex
ROOT=pathlib.Path(__file__).resolve().parents[2]
m=runpy.run_path(str(pathlib.Path(__file__).with_name('deploy-host-port-nat.py')))
report=json.loads(m['EVIDENCE'].read_text());commands=[]
def run(cmd,allow=False):
 out=m['run'](cmd,allow=allow);commands.append(m['REPORT']['commands'][-1]);return out
base="curl --noproxy '*' --connect-timeout 4 --max-time 8 --resolve home.iwonderful.top:8443:192.168.1.2 -sS -I https://home.iwonderful.top:8443/"
traffic={}
for host in ['home.iwonderful.top:8443','home.iwonderful.top:64443','home.iwonderful.top:65535','home.iwonderful.top:1','home.iwonderful.top','evil.test:64443','home.iwonderful.top.evil:64443','home.iwonderful.top:65536','home.iwonderful.top:0','home.iwonderful.top:0443','home.iwonderful.top:abc']:
 out=run(base+' -H '+shlex.quote('Host: '+host),allow=True);r=commands[-1];traffic[host]=r
 if host in ['home.iwonderful.top:8443','home.iwonderful.top:64443','home.iwonderful.top:65535','home.iwonderful.top:1','home.iwonderful.top']:
  assert r['code']==0 and out.startswith('HTTP/1.1 200'),r
 else:assert (r['code']!=0 and not out) or out.startswith('HTTP/1.1 400'),r
status=json.loads(run('ubus call homepublish status'))
for key in ['saved_config','saved_revision','desired_state','active_config','active_revision']:assert status[key]==report['before'][key],key
assert status['runtime']['phase']=='running' and status['runtime']['active_verified']
assert status['firewall']['state']=='open' and status['firewall']['rule_count']==report['before']['firewall']['rule_count']
assert run('sha256sum /etc/config/firewall /etc/config/homepublish')==report['uci_before']
sha=run('sha256sum /usr/share/homepublish/direct-renderer.lua').split()[0]
assert sha==hashlib.sha256((ROOT/'homepublish/files/usr/share/homepublish/direct-renderer.lua').read_bytes()).hexdigest()
report['initial_verifier_error']=report.pop('error',None);report['deployed']=True;report['verified']=True;report['verification_commands']=commands;report['traffic']=traffic;report['after']=status
m['EVIDENCE'].write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps({'deployed':True,'verified':True,'saved_revision':status['saved_revision'],'active_revision':status['active_revision'],'intent_before':report['before']['intent_revision'],'intent_after':status['intent_revision'],'firewall':status['firewall'],'sha256':sha,'traffic':{host:{'code':r['code'],'status':r['stdout'].splitlines()[:1]} for host,r in traffic.items()}},indent=2))
