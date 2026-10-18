"""Run P1 against deployed Lua/nixio only; no production lifecycle calls."""
import hashlib, pathlib, subprocess, shlex, sys
ROOT=pathlib.Path(__file__).resolve().parents[2]
REMOTE='/root/homepublish-lua-store/p1'
BASE=['-o','BatchMode=yes','-o','IdentitiesOnly=yes','-o','StrictHostKeyChecking=yes','-o','ProxyCommand=none','-o','ProxyJump=none','-i','D:/DevPortal/CloudHosts/HomePri.key']
EXPECTED='19234e3e06d55ebde10f2b64fd0517c3b0a02c0dee976ccc681d71989ceb58b9'
def ssh(cmd,check=True):
 p=subprocess.run(['ssh',*BASE,'root@192.168.1.2',cmd],text=True,capture_output=True)
 if check and p.returncode: raise RuntimeError(p.stdout+p.stderr)
 return p
def run(cases):
 allowed={'provider','errors','backup','product','sparse','journal','policy','revision','backup-write','backup-sync','backup-close'}
 if not set(cases)<=allowed: raise ValueError('unsupported case; no fallback: '+repr(cases))
 before=ssh('sha256sum /etc/homepublish/product/state').stdout.split()[0]
 assert before==EXPECTED, 'live baseline changed'
 for name in ('product-provider.lua','product-store.lua','product-store-core.lua','product-cli.lua'):
  expected=hashlib.sha256((ROOT/'homepublish/files/usr/share/homepublish'/name).read_bytes()).hexdigest()
  actual=ssh('sha256sum /usr/share/homepublish/'+name).stdout.split()[0]
  # Installed CLI is the reviewed CRLF byte variant; never upload business files.
  if name=='product-cli.lua':
   assert actual=='c3af588b7c4631fd08871822f0552f434f55e697b1abcd79979e32cc4cefc650', 'CLI changed'
  else: assert actual==expected, name+' deployed mismatch'
 ssh('umask 077; mkdir -p '+REMOTE+'/homepublish/tests; chmod 700 '+REMOTE)
 for name in ('device-p1-lua-scope.lua','device-tcp-p1-provider.lua','device-tcp-p1-backup.lua','device-tcp-p1-errors.lua','test-product-provider.lua','test-product-review.lua','test-canonical.lua'):
  local=ROOT/'homepublish/tests'/name
  remote=REMOTE+('/homepublish/tests/' if name=='test-canonical.lua' else '/')+name
  subprocess.run(['scp','-O',*BASE,str(local),'root@192.168.1.2:'+remote],check=True,capture_output=True)
  assert ssh('sha256sum '+remote).stdout.split()[0]==hashlib.sha256(local.read_bytes()).hexdigest()
 ssh("printf '%s\\n' \"dofile('"+REMOTE+"/device-p1-lua-scope.lua');arg={};dofile('/usr/share/homepublish/product-cli.lua')\" > "+REMOTE+'/cli.lua')
 results=[]
 try:
  for case in cases:
   ssh('rm -rf '+REMOTE+'/store')
   command={'provider':'device-tcp-p1-provider.lua','backup':'device-tcp-p1-backup.lua','errors':'device-tcp-p1-errors.lua','product':'test-product-provider.lua'}.get(case,'test-product-review.lua x '+shlex.quote(case))
   if case.startswith('backup-'):
    fault=case.split('-',1)[1]
    assert fault in ('write','sync','close')
    cmd='HP_BACKUP_FAIL='+fault+' lua '+REMOTE+'/device-tcp-p1-backup.lua fault'
   else: cmd='lua '+REMOTE+'/'+command
   p=ssh(cmd,False)
   print('CASE '+case+' exit='+str(p.returncode)+'\n'+p.stdout+p.stderr,flush=True)
   results.append(p.returncode)
 finally:
  after=ssh('sha256sum /etc/homepublish/product/state').stdout.split()[0]
  assert before==after,'LIVE JOURNAL CHANGED'
  print('LIVE_HASH_GUARD_GREEN '+after)
 return 1 if any(results) else 0
if __name__=='__main__': sys.exit(run(sys.argv[1:] or ['provider','errors','backup','product','sparse','journal','policy','revision']))
