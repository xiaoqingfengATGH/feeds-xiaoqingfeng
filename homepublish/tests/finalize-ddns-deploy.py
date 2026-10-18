import json,subprocess,hashlib,re,shlex
from pathlib import Path
R=Path('D:/DevPortal/Openwrt/feeds-xiaoqingfeng');E=R/'docs/evidence/lua-store/ddns-phase2-deploy';p=E/'deployment.json';d=json.loads(p.read_text());SSH=['ssh','-o','BatchMode=yes','-i','D:/DevPortal/CloudHosts/HomePri.key','root@192.168.1.2']
def run(s):return subprocess.check_output(SSH+[s]).decode()
s=json.loads(run("ubus call homepublish status '{}'"));runtime=json.loads(run("ubus call service list '{\"name\":\"homepublish-runtime\"}'"));controller=json.loads(run("ubus call service list '{\"name\":\"homepublish\"}'"))
# Recover the original before-read shape; explicit manual defaults were added only for comparison.
for key in ['saved_config','active_config']:
 for service in d['before']['status'][key]['services']:service.pop('dns',None)
d['initial_assertion_failure']='Before/after config equality initially rejected newly explicit dns.mode=manual defaults. Controller was then started with original revision 26 and preserved enabled intent; no save was performed.';d.pop('error',None);p.write_text(json.dumps(d,indent=2)+'\n')
for target,m in d['hashes'].items():assert run('sha256sum '+shlex.quote(target)).split()[0]==m['sha256']
assert s['runtime']['phase']=='running' and s['runtime']['active_verified'];assert all(v['ready'] for v in s['runtime']['services'].values());assert s['saved_revision']==s['active_revision']==26;assert s['desired_state']==d['before']['status']['desired_state'];assert all(x['dns']=={'mode':'manual'} for x in s['saved_config']['services'])
protection=run('sha256sum /etc/config/firewall /etc/config/homepublish /etc/ddns-go/config.yaml /etc/config/ddns-go');assert protection==d['before']['protected']
# Resolve socket inode owners without reading any configuration secrets.
fds=run('for p in /proc/[0-9]*; do n=$(cat "$p/comm" 2>/dev/null); case "$n" in nginx|sslh*) for f in "$p"/fd/*; do t=$(readlink "$f"); case "$t" in socket:*) printf "%s %s %s\\n" "${p##*/}" "$n" "$t";; esac; done;; esac; done')
tcp=run('cat /proc/net/tcp /proc/net/tcp6');owned=[]
for line in tcp.splitlines():
 cols=line.split()
 if len(cols)>9 and cols[3]=='0A':
  port=int(cols[1].split(':')[1],16);inode=cols[9]
  if 'socket:['+inode+']' in fds:owned.append({'endpoint_hex':cols[1],'port':port,'inode':inode,'owners':[x for x in fds.splitlines() if 'socket:['+inode+']' in x]})
assert {8443,50885}.issubset({x['port'] for x in owned}),owned
allsyntax=run("for p in /usr/share/homepublish/*.lua; do lua -e \"assert(loadfile('$p'))\" || exit 1; done; printf ALL_INSTALLED_LUA_SYNTAX_OK")
result={'status':s,'runtime_procd':runtime,'controller':controller,'owned_listeners':owned,'all_installed_lua_syntax':allsyntax,'protected':protection,'journal':run('sha256sum /etc/homepublish/product/state'),'deployed_file_count':len(d['hashes']),'installed_ui_test_case_count':len(json.loads((E/'installed-ui-tests.json').read_text())['results'])}
(E/'final-health.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps({'controller_pid':controller['homepublish']['instances']['controller']['pid'],'runtime_phase':s['runtime']['phase'],'saved_revision':s['saved_revision'],'active_revision':s['active_revision'],'generation':s['runtime']['generation'],'owned_ports':sorted({x['port'] for x in owned}),'syntax':allsyntax,'protected_unchanged':True,'hash_count':len(d['hashes'])}))
