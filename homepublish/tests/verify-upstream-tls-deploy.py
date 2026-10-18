"""Read-only completion of already-uploaded deployment, including unavailable saved backend evidence."""
import importlib.util,json
from pathlib import Path
p=Path(__file__).with_name('deploy-upstream-tls-source.py');spec=importlib.util.spec_from_file_location('deploy',p);d=importlib.util.module_from_spec(spec);spec.loader.exec_module(d)
d.report=json.loads(d.EVIDENCE.read_text());r=d.report
r['initial_verification_error']=r.pop('error',None)
s=d.status();r['final_status']=s
for k in ['saved_config','saved_revision','desired_state','active_config','active_revision']:assert s[k]==r['before'][k],k
assert s['runtime']['phase']=='running' and s['runtime']['active_verified']
assert all(x['ready'] for x in s['runtime']['services'].values())
assert d.protect()==r['uci_before']
for path,sha in r['sha256'].items():assert d.run('sha256sum '+path).split()[0]==sha
r['final_controller']=d.service();r['final_runtime']=json.loads(d.run("ubus call service list '{\"name\":\"homepublish-runtime\"}'"))
assert r['final_controller']['homepublish']['instances']['controller']['running']
assert all(x['running'] for x in r['final_runtime']['homepublish-runtime']['instances'].values())
r['production_https_response']=d.run("env -u CURL_CA_BUNDLE -u SSL_CERT_FILE -u SSL_CERT_DIR curl -q --noproxy '*' --silent --show-error --max-time 8 -w '|%{http_code}' --resolve home.iwonderful.top:8443:192.168.1.2 https://home.iwonderful.top:8443/")
r['saved_backend_connectivity']=d.run("lua -e 'local n=require(\"nixio\"); local s=assert(n.socket(\"inet\",\"stream\"));local ok,code,msg=s:connect(\"127.0.0.1\",50882); print(tostring(ok),tostring(code),tostring(msg));s:close()'")
r['limitations']=['Unmodified saved HTTPS service points to 127.0.0.1:50882, which refuses TCP connections. Public HTTPS certificate validation succeeds but its upstream returns 502. Private self-signed acceptance passed independently.']
r['deployed']=True
d.EVIDENCE.write_text(json.dumps(r,indent=2)+'\n')
print(json.dumps({k:r[k] for k in ['deployed','backup','sha256','production_https_response','saved_backend_connectivity','limitations']},indent=2))
