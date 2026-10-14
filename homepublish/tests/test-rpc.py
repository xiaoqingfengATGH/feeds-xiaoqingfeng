#!/usr/bin/env python3
"""Real rpcd plugin subprocess -> fixed CLI -> native durable store (no fake backend)."""
import importlib.util, json, os, pathlib, subprocess, tempfile
ROOT=pathlib.Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('controller',ROOT/'homepublish/tests/test-controller.py'); c=importlib.util.module_from_spec(spec);spec.loader.exec_module(c)
PLUGIN=ROOT/'luci-app-homepublish/root/usr/libexec/rpcd/homepublish'
def main():
 with tempfile.TemporaryDirectory(prefix='rpc-',dir='/home/eric/homestun-sdk-check') as td:
  d=pathlib.Path(td)
  subprocess.run(['cc','-std=c99','-Wall','-Wextra','-Werror','-Wno-misleading-indentation','-fPIC','-shared','-I'+c.DEV+'/lua5.1','-I'+c.DEV+'/x86_64-linux-gnu','-DPRODUCT_ROOT='+json.dumps(str(d/'store')),str(c.SRC/'product-store.c'),'-o',str(d/'homepublish_store.so')],check=True)
  # Copy fixed plugin to private fixture and bind only its hardcoded installed paths.
  script=PLUGIN.read_text().replace('/usr/bin/lua',c.LUA).replace('/usr/share/homepublish',str(c.SHARE))
  p=d/'homepublish';p.write_text(script);p.chmod(0o755)
  env={**os.environ,'LUA_CPATH':str(d/'?.so')}
  methods=json.loads(subprocess.check_output([str(p),'list'],env=env));assert set(methods)=={'status','validate','save','stop','start','apply','certificates'},methods
  def rpc(method,args={}):
   r=subprocess.run([str(p),'call',method],input=json.dumps(args),text=True,capture_output=True,env=env,timeout=3)
   assert r.returncode==0,(r.stdout,r.stderr);return json.loads(r.stdout)
  cfg={'schema_version':1,'services':[{'service_id':'nas','name':'NAS','hostname':'nas.example.test','backend':{'host':'192.168.1.10','port':8080,'allowed_ranges':['192.168.1.0/24']},'certificate_ref':'acme:nas','authentication_review':{'authentication':'confirmed','management':False}}],'access_profile':{'methods_allowed':['manual_ipv4'],'listeners':[{'family':'ipv4','address':'192.168.1.2','interface':'wan','zone':'wan','protocol':'tcp','internal_port':8443,'external_port':18443}]}}
  assert rpc('status',{'ubus_rpc_session':'a'*32})['saved_revision']==0
  assert rpc('status')['saved_revision']==0
  assert 'error' in rpc('start',{'revision':0,'approved':True})
  assert 'error' in rpc('apply',{'revision':0,'approved':True})
  v=rpc('validate',{'config':cfg});assert v['valid'] and v['config']['publication_policy']=={'mode':'continuous','boot_restore':False}
  assert rpc('status')['saved_revision']==0
  s=rpc('save',{'expected_revision':0,'config':cfg});assert s['saved_revision']==1 and s['pending_config']['apply_required'] and 'active_revision' not in s
  assert rpc('status')['saved_config']==s['saved_config']
  assert 'error' in rpc('save',{'expected_revision':0,'config':cfg})
  assert 'error' in rpc('status',{'path':'/etc/config/firewall'})
  cfg['services'][0]['name']='家庭 NAS 😀'
  s=rpc('save',{'expected_revision':1,'config':cfg});assert s['saved_revision']==2 and s['saved_config']['services'][0]['name']=='家庭 NAS 😀'
  assert rpc('status')['saved_config']==s['saved_config']
  s=rpc('stop');assert s['desired_state']['manual_stop_latch'] and s['desired_state']['state']=='disabled'
  assert rpc('status')['desired_state']==s['desired_state']
  print('PASS scoped plugin actual CLI cross-process validate/save/status/pending/conflict/stop latch')
if __name__=='__main__':main()
