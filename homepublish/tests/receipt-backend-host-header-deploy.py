import importlib.util,json,hashlib
from pathlib import Path
R=Path('D:/DevPortal/Openwrt/feeds-xiaoqingfeng');spec=importlib.util.spec_from_file_location('deploy',R/'homepublish/tests/deploy-backend-host-header.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
d=json.loads((m.E/'deployment.json').read_text());ui=json.loads((m.E/'installed-native-ui.json').read_text());s=m.status()
assert d['deployed'];assert ui['native']['code']==0 and ui['native_validation']['valid'] and ui['actual_saved_plus_native_host_validation']['valid']
assert m.protect()==d['protected_before']
for k in ['saved_config','active_config','saved_revision','active_revision','desired_state']:assert s[k]==d['before'][k],k
assert s['runtime']['phase']=='running' and s['runtime']['active_verified'];assert all(v['ready'] for v in s['runtime']['services'].values())
for p,want in d['sha256'].items():assert m.run('sha256sum '+p).split()[0]==want
assert m.rpc('ddns_profiles')==d['profiles']
traffic=m.run("env -u CURL_CA_BUNDLE -u SSL_CERT_FILE -u SSL_CERT_DIR curl -q --noproxy '*' --silent --show-error --max-time 12 --resolve vmware.innonext.win:8443:192.168.1.2 -o /dev/null -w 'HTTP %{http_code} verified_tls=%{ssl_verify_result}\\n' https://vmware.innonext.win:8443/")
assert traffic.strip()=='HTTP 200 verified_tls=0'
manifest={'deployed':True,'sha256':d['sha256'],'backup':d['backup'],'saved_revision':s['saved_revision'],'active_revision':s['active_revision'],'generation':s['runtime']['generation'],'enabled':s['desired_state']['state'],'boot_restore':s['saved_config']['publication_policy']['boot_restore'],'active_verified':True,'all_services_ready':True,'protected_settings_unchanged':True,'ddns_profiles_unchanged':True,'ddns_ensure_receipt':d['normal_start_result']['ddns'],'new_configured_domains':False,'native_installed_ui_pass':True,'native_captured_payload_valid':True,'production_host_override_configured':False,'https_smoke':traffic.strip()}
(m.E/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n');(m.E/'final-readonly-status.json').write_text(json.dumps(s,indent=2)+'\n');print(json.dumps(manifest,indent=2))
