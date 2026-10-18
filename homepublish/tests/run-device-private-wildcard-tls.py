"""Read-only production inspection + private installed-nginx wildcard TLS test."""
import subprocess,json,uuid,pathlib,shlex,sys
REPO=pathlib.Path('D:/DevPortal/Openwrt/feeds-xiaoqingfeng')
SSH=['ssh','-o','ProxyCommand=none','-o','ProxyJump=none','-o','IdentitiesOnly=yes','-o','BatchMode=yes','-i','D:/DevPortal/CloudHosts/HomePri.key','root@192.168.1.2']
tag='wildcard-tls-'+uuid.uuid4().hex[:12]
evidence={'tag':tag,'scope':'Private loopback nginx; no production restart/configuration/firewall mutation'}
def run(cmd,check=True):
 p=subprocess.run(SSH+[cmd],capture_output=True,text=True,timeout=60)
 r={'command':cmd,'returncode':p.returncode,'stdout':p.stdout,'stderr':p.stderr}
 if check and p.returncode: raise RuntimeError(json.dumps(r))
 return r
def lua(code): return run('lua -e '+shlex.quote('package.path="/usr/share/homepublish/?.lua;"..package.path;'+code))
def baseline():
 s=json.loads(run("ubus call homepublish status '{}' ")['stdout'])
 return {'hashes':run('sha256sum /etc/homepublish/product/state /etc/config/firewall /usr/libexec/homepublish/nginx /tmp/homepublish-runtime/nginx.conf')['stdout'],'saved_revision':s['saved_revision'],'active_revision':s['active_revision'],'intent_revision':s['intent_revision'],'generation':s['runtime']['generation'],'phase':s['runtime']['phase'],'saved_config':s['saved_config'],'active_config':s['active_config'],'production_processes':run("for p in /proc/[0-9]*/cmdline; do c=$(tr '\\000' ' ' < \"$p\" 2>/dev/null); case \"$c\" in 'nginx: master process /usr/libexec/homepublish/nginx '*|'/usr/libexec/homepublish/nginx '*|'/usr/libexec/homepublish/sslh '*) printf '%s %s\\n' \"$p\" \"$c\";; esac; done")['stdout']}
try:
 evidence['before']=baseline()
 evidence['nginx_version']=run('/usr/libexec/homepublish/nginx -V 2>&1')['stdout']
 code='local D=require("device-integrations");local s,e=D.certificate_source("acme:*.innonext.win","vm.innonext.win");assert(s,e);local n=require("nixio");local sock=assert(n.socket("inet","stream"));assert(sock:bind("127.0.0.1",0));local a,p=sock:getsockname();sock:close();local m=require("certificate-metadata").read(s.certificate);local checks={};for _,h in ipairs({"vm.innonext.win","innonext.win","a.b.innonext.win"}) do local ok,err=D.certificate_source("acme:*.innonext.win",h);checks[h]={accepted=ok~=nil,error=err} end;print(require("luci.jsonc").stringify({source=s,metadata=m,port=p,provider_checks=checks}));'
 resolved=json.loads(lua(code)['stdout']); evidence['certificate']=resolved
 root='/root/homepublish-lua-store/'+tag;port=resolved['port'];src=resolved['source']
 conf=f'''worker_processes 1;
master_process on;
pid {root}/nginx.pid;
error_log {root}/error.log notice;
events {{ worker_connections 32; }}
http {{ access_log off; server {{ listen 127.0.0.1:{port} ssl; server_name vm.innonext.win; ssl_certificate "{src['certificate']}"; ssl_certificate_key "{src['key']}"; location / {{ default_type text/plain; return 200 "{tag}\\n"; }} }} }}
'''
 shell=f'''set -eu
umask 077
root={shlex.quote(root)}
mkdir -p "$root/logs"
cleanup() {{
 if [ -f "$root/nginx.pid" ]; then
  p=$(cat "$root/nginx.pid")
  case "$p" in ''|*[!0-9]*) exit 92;; esac
  c=$(tr '\\000' ' ' < /proc/$p/cmdline 2>/dev/null || true)
  case "$c" in *"$root"*) kill -TERM "$p";; *) echo CLEANUP_IDENTITY_MISMATCH; exit 93;; esac
  i=0; while kill -0 "$p" 2>/dev/null && [ "$i" -lt 10 ]; do sleep 1; i=$((i+1)); done
  if kill -0 "$p" 2>/dev/null; then echo CLEANUP_PROCESS_STILL_ALIVE; exit 94; fi
 fi
 rm -rf "$root"
 echo PRIVATE_PROCESS_AND_ROOT_REMOVED
}}
trap cleanup EXIT HUP INT TERM
printf %s {shlex.quote(conf)} > "$root/nginx.conf"
/usr/libexec/homepublish/nginx -p "$root/" -c "$root/nginx.conf" -t
/usr/libexec/homepublish/nginx -p "$root/" -c "$root/nginx.conf"
sleep 1
for h in vm.innonext.win innonext.win a.b.innonext.win; do
 echo "TLS_HOST=$h"
 set +e
 curl --noproxy '*' --connect-timeout 5 --max-time 10 --resolve "$h:{port}:127.0.0.1" -sS -w '\\nHTTP_CODE=%{{http_code}} SSL_VERIFY=%{{ssl_verify_result}}\\n' "https://$h:{port}/"
 rc=$?
 set -e
 echo "CURL_EXIT=$rc"
 if [ "$h" = vm.innonext.win ]; then [ "$rc" = 0 ]; else [ "$rc" = 60 ]; fi
done
'''
 evidence['private_test']=run(shell,False)
 evidence['after']=baseline()
 evidence['production_unchanged']=evidence['before']==evidence['after']
 evidence['cleanup_readback']=run('test ! -e '+shlex.quote(root)+' && ! netstat -lnt 2>/dev/null | grep -F '+shlex.quote('127.0.0.1:'+str(port)+' '),False)
 evidence['passed']=evidence['private_test']['returncode']==0 and evidence['production_unchanged'] and evidence['cleanup_readback']['returncode']==0
except Exception as e:
 evidence['error']=str(e);evidence['passed']=False
out=REPO/'docs/evidence/lua-store'/f'{tag}.json';out.write_text(json.dumps(evidence,indent=2),encoding='utf-8')
print(json.dumps({'evidence':str(out),'passed':evidence['passed'],'private_test':evidence.get('private_test'),'production_unchanged':evidence.get('production_unchanged'),'error':evidence.get('error')},indent=2))
sys.exit(0 if evidence['passed'] else 1)
