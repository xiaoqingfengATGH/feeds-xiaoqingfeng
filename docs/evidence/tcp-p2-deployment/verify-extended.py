"""Read-only final verification; never deploy/restore or mutate live state."""
import hashlib, json, pathlib, subprocess, urllib.request
ROOT = pathlib.Path(__file__).resolve().parents[3]
SSH = ['ssh','-o','ProxyCommand=none','-o','ProxyJump=none','-o','IdentitiesOnly=yes','-o','BatchMode=yes','-i','D:/DevPortal/CloudHosts/HomePri.key','-p','222','root@127.0.0.1']
def remote(cmd):
    return subprocess.check_output(SSH+[cmd], timeout=45)
manifest = json.loads((ROOT/'docs/evidence/tcp-p2-deployment/deployment-manifest.json').read_text())
checks = []
for entry in manifest['files']:
    source = pathlib.Path(entry['source']).read_bytes()
    installed = remote('cat '+entry['target'])
    assert source == installed, entry['target']
    if entry['target'].startswith('/www/'):
        served = urllib.request.urlopen('http://127.0.0.1:1081'+entry['target'][4:]+'?p2-final=1',timeout=20).read()
        assert served == installed, 'served mismatch '+entry['target']
    checks.append({'target':entry['target'],'sha256':hashlib.sha256(installed).hexdigest(),'source_matches':True})
assert len(checks) == 39
backup = manifest['backup']
private = remote('sha256sum -c '+backup+'/private.sha256; sha256sum -c '+backup+'/config.sha256').decode()
assert 'FAILED' not in private
status = json.loads(remote("ubus call homepublish status '{}'"))
assert status['saved_revision'] == 0 and status['intent_revision'] == 7
assert status['desired_state']['state'] == 'disabled' and status['desired_state']['manual_stop_latch'] is True
assert status['runtime']['phase'] == 'stopped' and status['runtime']['cleanup'] == 'confirmed'
print(json.dumps({'file_count':len(checks),'files':checks,'private_config_checks':private,'live_status':status},indent=2))
