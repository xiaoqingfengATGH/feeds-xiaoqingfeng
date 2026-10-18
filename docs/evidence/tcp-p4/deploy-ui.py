import pathlib,subprocess,hashlib,json,datetime
R=pathlib.Path('D:/DevPortal/homelede/homepublish-product')
opts=['-o','ProxyCommand=none','-o','ProxyJump=none','-o','IdentitiesOnly=yes','-o','BatchMode=yes','-i','D:/DevPortal/CloudHosts/HomePri.key']
def remote(cmd):return subprocess.check_output(['ssh',*opts,'-p','222','root@127.0.0.1',cmd],text=True,timeout=45)
backup='/root/homepublish-p4-ui-backup/'+datetime.datetime.now().strftime('%Y%m%d-%H%M%S')
base=R/'luci-app-homepublish/htdocs/luci-static/resources/view/homepublish'
target='/www/luci-static/resources/view/homepublish/'
before=json.loads(remote('ubus call homepublish status'))
remote('umask 077; mkdir -p '+backup+'; cp '+target+'product.js '+target+'overview.js '+backup+'/')
files=[]
for name in ['product.js','overview.js']:
 p=base/name
 subprocess.run(['scp','-O',*opts,'-P','222',p.resolve().as_posix(),'root@127.0.0.1:'+target+name],check=True,capture_output=True,timeout=45)
 actual=remote('sha256sum '+target+name).split()[0];expected=hashlib.sha256(p.read_bytes()).hexdigest();assert actual==expected
 files.append({'name':name,'sha256':actual})
after=json.loads(remote('ubus call homepublish status'))
for key in ['saved_revision','active_revision','saved_config','active_config','desired_state']:
 assert before.get(key)==after.get(key),key
assert after['saved_revision']==0
assert after['desired_state']['state']=='disabled'
assert after['desired_state']['manual_stop_latch'] is True
assert after['runtime']['phase']=='stopped'
print(json.dumps({'backup':backup,'files':files,'before':before,'after':after},ensure_ascii=False,indent=2))
