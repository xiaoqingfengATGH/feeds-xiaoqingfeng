import pathlib,subprocess,json
repo=pathlib.Path(__file__).resolve().parents[1]
ssh=['ssh','-F','/dev/null','-i','D:/DevPortal/CloudHosts/HomePri.key','-p','222','-o','BatchMode=yes','root@127.0.0.1']
base='ubus -s /tmp/homestun-luci-isolated/var/run/ubus/ubus.sock '
def call(obj,method,args):
 s=json.dumps(args);cmd=base+'call '+obj+' '+method+" '"+s+"'";p=subprocess.run(ssh+[cmd],capture_output=True,check=True);return json.loads(p.stdout or b'{}')
sid=call('session','create',{'timeout':600})['ubus_rpc_session']
acl=json.loads((repo/'luci-app-homestun/root/usr/share/rpcd/acl.d/luci-app-homestun.json').read_text())['luci-app-homestun']
objects=[['homestun','status'],['uci','get'],['uci','changes'],['uci','set'],['uci','add'],['uci','delete'],['uci','order'],['session','access']]
for method in acl.get('write',{}).get('ubus',{}).get('uci',[]):objects.append(['uci',method])
call('session','grant',{'ubus_rpc_session':sid,'scope':'ubus','objects':objects})
call('session','grant',{'ubus_rpc_session':sid,'scope':'uci','objects':[['homestun','read'],['homestun','write'],['other','read'],['other','write'],['luci','read']]})
call('session','set',{'ubus_rpc_session':sid,'values':{'acls':{'luci-app-homestun':['read','write']}}})
call('uci','set',{'ubus_rpc_session':sid,'config':'other','section':'main','values':{'value':'staged-other'}})
(repo/'docs/artifacts/luci-fixture-session.json').write_text(json.dumps({'sid':sid}))
print('Fixture session initialized using production homestun ACL; unrelated config staged')
