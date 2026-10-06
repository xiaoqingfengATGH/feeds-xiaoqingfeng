#!/usr/bin/env python3
"""Isolated real RPC subprocess test; UCI inputs only are fixtures.
Requires BusyBox ash, genuine libubox jshn.sh + jshn binary, and OpenSSL.
Never invokes production services or writes production configuration.
"""
import base64
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import uuid

src, jshn, jshnbin = map(Path, sys.argv[1:4])
busybox = shutil.which('busybox')
assert busybox and jshn.is_file() and jshnbin.is_file()
with tempfile.TemporaryDirectory(prefix='homevpn-sswan-test-') as td:
    t = Path(td)
    os.chmod(t, 0o700)
    (t/'bin').mkdir()
    (t/'certs/x509ca').mkdir(parents=True)
    (t/'tmp').mkdir()
    shutil.copy2(jshnbin, t/'bin/jshn')
    lib=src.parents[2]/'share/homevpn/selfsigned-pki.sh'
    subprocess.run([busybox,'ash','-c',f'. {lib}; CA_DIR={t}/certs/x509ca; KEY_DIR={t}/certs/private; X509_DIR={t}/certs/x509; hv_pki_ensure_ca 0 && hv_pki_sync_leaf vpn.example.test'],check=True,capture_output=True)
    shutil.copy2(t/'certs/x509ca/homevpn-ca.crt',t/'ca')
    der=subprocess.check_output(['openssl','x509','-in',str(t/'ca'),'-outform','DER'])
    cap=t/'certs/x509ca/homevpn-ca.crt'
    shutil.copy2(t/'ca',cap)
    source=src.read_text()
    source=source.replace('. /usr/share/libubox/jshn.sh', '. '+str(jshn))
    source=source.replace('SWANCTL="/etc/swanctl"','SWANCTL="'+str(t/'certs')+'"')
    source=source.replace('ACME_RESOLVER="/usr/share/homevpn/acme-resolve.sh"','ACME_RESOLVER="/dev/null"')
    source=source.replace('/tmp/homevpn-sswan.',str(t/'tmp/homevpn-sswan.'))
    source=source.replace('/usr/share/homevpn/selfsigned-pki.sh',str(lib))
    lock=t/'lock-lib'; lock.write_text((src.parents[2]/'share/homevpn/service-lock.sh').read_text().replace('/var/lock/homevpn-service.lock',str(t/'lock')))
    source=source.replace('/usr/share/homevpn/service-lock.sh',str(lock))
    rpc=t/'rpc'; rpc.write_text(source)
    uci=t/'bin/uci'
    uci.write_text('''#!/usr/bin/env python3
import json,os,sys
from pathlib import Path
p=Path(os.environ['FIXTURE'])
k=sys.argv[-1]
with (p/'reads').open('a') as f: f.write(k+'\\n')
d=json.loads((p/'config.json').read_text())
if k not in d: sys.exit(1)
print(d[k])
''')
    uci.chmod(0o700)
    (t/'bin/ip').write_text('#!/bin/sh\nexit 1\n'); (t/'bin/ip').chmod(0o700)
    env=dict(os.environ,PATH=str(t/'bin')+':'+os.environ['PATH'],FIXTURE=str(t))
    def cfg(name='Home VPN',remote='vpn.example.test'):
        (t/'config.json').write_text(json.dumps({'homevpn.config.remote':remote,
            'homevpn.config.vpn_name':name,'homevpn.config.cert_mode':'selfsigned',
            'homevpn.@user[0]':'user','homevpn.@user[0].name':'alice',
            'homevpn.@user[0].password':'FIXTURE_PASSWORD_SENTINEL'}))
    def call(user='alice',kind='sswan'):
        result=subprocess.run([busybox,'ash',str(rpc),'call','download'],
            input=json.dumps({'name':user,'what':kind})+'\n',text=True,capture_output=True,env=env,check=True)
        assert 'FIXTURE_PASSWORD_SENTINEL' not in result.stdout
        assert not list((t/'tmp').iterdir()), 'temporary conversion artifacts leaked'
        return json.loads(result.stdout)
    cfg()
    out=call(); assert out['ok'] is True and out['name']=='alice'
    profile=json.loads(out['sswan'])
    assert set(profile)=={'uuid','name','type','remote','local'}, 'wrong profile fields'
    assert profile['remote']=={'addr':'vpn.example.test','id':'vpn.example.test','cert':base64.b64encode(der).decode()}
    assert profile['local']=={'id':'alice','eap_id':'alice'}
    assert profile['type']=='ikev2-eap'
    first=uuid.UUID(profile['uuid']); assert first.version==4
    assert uuid.UUID(json.loads(call()['sswan'])['uuid'])!=first
    for name in ['中文 VPN','quote " slash \\ and\nline']:
        cfg(name); assert json.loads(call()['sswan'])['name']==name
    cfg(); assert call('missing')['ok'] is False
    cfg(remote=''); assert call()['ok'] is False
    cfg(); cap.unlink(); assert call()['ok'] is False
    cap.touch(); assert call()['ok'] is False
    cap.write_text('invalid PEM'); assert call()['ok'] is False
    shutil.copy2(t/'ca',cap)
    for tool in ['openssl','base64','mktemp']:
        # BusyBox ash may prefer built-in applets to PATH. Inject failure at
        # the command boundary, never replace serialization or RPC logic.
        rpc.write_text(tool+'() { return 1; }\n'+source)
        assert call()['ok'] is False, tool+' failure must fail closed'
        rpc.write_text(source)
    # Distinct fixture CA proves existing numbered-chain/legacy/self order.
    subprocess.run(['openssl','req','-x509','-newkey','rsa:2048','-nodes','-subj','/CN=Other CA',
        '-days','1','-keyout',str(t/'other.key'),'-out',str(t/'other.ca')],
        check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    other=base64.b64encode(subprocess.check_output(['openssl','x509','-in',str(t/'other.ca'),'-outform','DER'])).decode()
    legacy=cap.parent/'homevpn-acme.crt'; shutil.copy2(t/'other.ca',legacy)
    for mode in ['import','acme','selfsigned']:
        d=json.loads((t/'config.json').read_text()); d['homevpn.config.cert_mode']=mode
        (t/'config.json').write_text(json.dumps(d))
        expected=base64.b64encode(der).decode() if mode=='selfsigned' else other
        assert json.loads(call()['sswan'])['remote']['cert']==expected
    numbered=cap.parent/'homevpn-acme-02.crt'; shutil.copy2(t/'ca',numbered)
    assert json.loads(call()['sswan'])['remote']['cert']==base64.b64encode(der).decode()
    numbered.unlink(); legacy.unlink()
    assert not any('.password' in x for x in (t/'reads').read_text().splitlines())
    print('PASS: real BusyBox ash + libubox jshn RPC; exact DER, identities, nested JSON, Unicode/escaping, UUID, missing inputs, malformed CA and no password reads')
