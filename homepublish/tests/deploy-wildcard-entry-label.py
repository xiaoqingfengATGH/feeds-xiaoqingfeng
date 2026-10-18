"""Deploy only exact requested entry wording, no browser refresh or lifecycle."""
import hashlib,json,subprocess
from pathlib import Path
R=Path(__file__).resolve().parents[2]
SSH=['ssh','-o','ProxyCommand=none','-o','ProxyJump=none','-o','IdentitiesOnly=yes','-o','BatchMode=yes','-i','D:/DevPortal/CloudHosts/HomePri.key','root@192.168.1.2']
def run(cmd,data=None):
 p=subprocess.run(SSH+[cmd],input=data,capture_output=True,timeout=60);assert p.returncode==0,p.stderr.decode();return p.stdout.decode()
def main():
 target='/www/luci-static/resources/view/homepublish/entry.js';backup='/root/homepublish-lua-store/wildcard-deploy-270756875d26'
 data=(R/'luci-app-homepublish/htdocs/luci-static/resources/view/homepublish/entry.js').read_bytes()
 text='仅供 HTTPS 反代 使用。HTTP 反代、TLS 透传、SSH 和 TCP 转发不需要本机证书。'
 assert text in data.decode();before=json.loads(run("ubus call homepublish status '{}'"));uci=run('sha256sum /etc/config/firewall /etc/config/homepublish')
 run('cp '+target+' '+backup+'/entry.js.before; cat > '+target+'.wildcard-new && chmod 644 '+target+'.wildcard-new && mv '+target+'.wildcard-new '+target,data)
 sha=run('sha256sum '+target).split()[0];assert sha==hashlib.sha256(data).hexdigest()
 after=json.loads(run("ubus call homepublish status '{}'"))
 for key in ['saved_config','saved_revision','active_config','active_revision','desired_state']:assert before[key]==after[key],key
 assert uci==run('sha256sum /etc/config/firewall /etc/config/homepublish')
 result={'deployed':True,'target':target,'sha256':sha,'exact_description':text,'saved_revision':after['saved_revision'],'active_revision':after['active_revision'],'browser_refreshed':False}
 (R/'docs/evidence/input-firewall/wildcard-entry-label-deploy.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
 print(json.dumps(result,ensure_ascii=True))
if __name__=='__main__':main()
