"""Deploy only proven Host/NAT renderer fix to authorized router, no save/fw reload."""
import hashlib,json,pathlib,shlex,subprocess,time,uuid
REPO=pathlib.Path(__file__).resolve().parents[2]
SSH=['ssh','-i','D:/DevPortal/CloudHosts/HomePri.key','-o','BatchMode=yes','-o','IdentitiesOnly=yes','-o','ProxyCommand=none','-o','ProxyJump=none','root@192.168.1.2']
TARGET='/usr/share/homepublish/direct-renderer.lua'
BACKUP='/root/homepublish-lua-store/host-nat-'+uuid.uuid4().hex[:12]
REPORT={'backup':BACKUP,'commands':[],'deployed':False}
EVIDENCE=REPO/'docs/evidence/input-firewall/host-port-nat-deploy.json'
def run(cmd,data=None,allow=False):
 p=subprocess.run(SSH+[cmd],input=data,capture_output=True,timeout=60)
 r={'command':cmd,'code':p.returncode,'stdout':p.stdout.decode(errors='replace'),'stderr':p.stderr.decode(errors='replace')};REPORT['commands'].append(r)
 if p.returncode and not allow: raise RuntimeError(r)
 return r['stdout']
def status():return json.loads(run('ubus call homepublish status'))
def main():
 try:
  before=status();REPORT['before']=before
  assert before['runtime']['phase']=='running' and before['saved_revision']==19
  protected=run('sha256sum /etc/config/firewall /etc/config/homepublish');REPORT['uci_before']=protected
  REPORT['nft_before']=run('nft list chain inet fw4 input_lan; nft list set inet fw4 homepublish_in4_lan')
  old=run('cat '+TARGET)
  data=(REPO/'homepublish/files/usr/share/homepublish/direct-renderer.lua').read_bytes()
  # Refuse unrelated remote/local divergence: only Host guard block may differ.
  start='  -- Match';end="  out[#out+1]='server { '"
  def strip_guard(text):return text[:text.index(start)]+text[text.index(end):]
  assert strip_guard(old)==strip_guard(data.decode()),'unrelated renderer divergence'
  run('umask 077; mkdir '+BACKUP+'; cp '+TARGET+' '+BACKUP+'/direct-renderer.lua; cp /etc/homepublish/product/state '+BACKUP+'/state; cp /tmp/homepublish-runtime/nginx.conf '+BACKUP+'/nginx.conf')
  run('cat > '+TARGET+'.host-nat-new && lua -e '+shlex.quote("assert(loadfile('"+TARGET+".host-nat-new'))")+' && chmod 644 '+TARGET+'.host-nat-new && mv '+TARGET+'.host-nat-new '+TARGET,data)
  REPORT['sha256']=run('sha256sum '+TARGET).split()[0];assert REPORT['sha256']==hashlib.sha256(data).hexdigest()
  controller=json.loads(run("ubus call service list '{\"name\":\"homepublish\"}'"));oldpid=controller['homepublish']['instances']['controller']['pid']
  run("ubus call service delete '{\"name\":\"homepublish\"}'")
  for _ in range(60):
   if run('test ! -d /proc/'+str(oldpid)+'; printf "%s" "$?"').strip()=='0':break
   time.sleep(.25)
  else:raise RuntimeError('controller did not exit')
  run('/etc/init.d/homepublish start')
  for _ in range(60):
   try:
    restored=status()
    if restored['runtime']['phase']=='stopped':break
   except Exception:pass
   time.sleep(.25)
  else:raise RuntimeError('controller not restored stopped')
  for key in ['saved_config','saved_revision','desired_state','active_config','active_revision']:
   assert restored[key]==before[key],key
  payload=json.dumps({'action':'start','revision':before['saved_revision'],'approved':True})
  REPORT['start']=json.loads(run('printf "%s\\n" '+shlex.quote(payload)+' | lua /usr/share/homepublish/product-device-cli.lua'))
  for _ in range(60):
   after=status()
   if after['runtime']['phase']=='running' and after['runtime'].get('active_verified'):break
   time.sleep(.25)
  REPORT['after']=after
  for key in ['saved_config','saved_revision','desired_state','active_config','active_revision']:
   assert after[key]==before[key],key
  assert after['runtime']['phase']=='running' and after['runtime']['active_verified']
  assert after['firewall']['state']=='open' and after['firewall']['rule_count']==before['firewall']['rule_count']
  REPORT['uci_after']=run('sha256sum /etc/config/firewall /etc/config/homepublish');assert protected==REPORT['uci_after']
  REPORT['nginx_after']=run('cat /tmp/homepublish-runtime/nginx.conf')
  REPORT['nft_after']=run('nft list chain inet fw4 input_lan; nft list set inet fw4 homepublish_in4_lan')
  REPORT['traffic']={}
  base="curl --noproxy '*' --connect-timeout 4 --max-time 8 --resolve home.iwonderful.top:8443:192.168.1.2 -sS -I https://home.iwonderful.top:8443/"
  for host in ['home.iwonderful.top:8443','home.iwonderful.top:64443','home.iwonderful.top:65535','home.iwonderful.top','evil.test:64443','home.iwonderful.top.evil:64443','home.iwonderful.top:65536','home.iwonderful.top:0','home.iwonderful.top:0443']:
   out=run(base+' -H '+shlex.quote('Host: '+host),allow=True);r=REPORT['commands'][-1];REPORT['traffic'][host]=r
   if host in ['home.iwonderful.top:8443','home.iwonderful.top:64443','home.iwonderful.top:65535','home.iwonderful.top']:
    assert r['code']==0 and out.startswith('HTTP/1.1 200'),r
   else:assert (r['code']!=0 and not out) or out.startswith('HTTP/1.1 400'),r
  REPORT['deployed']=True
 except Exception as e:REPORT['error']=repr(e)
 finally:
  EVIDENCE.parent.mkdir(parents=True,exist_ok=True);EVIDENCE.write_text(json.dumps(REPORT,indent=2)+'\n')
 print(json.dumps({k:REPORT.get(k) for k in ['deployed','backup','sha256','error','traffic']},indent=2))
 return 0 if REPORT['deployed'] else 1
if __name__=='__main__':raise SystemExit(main())
