#!/usr/bin/env python3
"""Execute retained certificate contracts on target Lua/nixio in a private root."""
import ast
import io
from pathlib import Path
import subprocess
import tarfile
import uuid
HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[1]

def run():
    remote='/tmp/homepublish-cert-contract-'+uuid.uuid4().hex
    ssh=['ssh','-o','BatchMode=yes','-o','IdentitiesOnly=yes','-o','ConnectTimeout=8','-i','D:/DevPortal/CloudHosts/HomePri.key','root@192.168.1.2']
    buf=io.BytesIO()
    with tarfile.open(fileobj=buf,mode='w') as tar:
        for source in (ROOT/'homepublish/files/usr/share/homepublish').glob('*.lua'):
            body=source.read_bytes().replace(b'\r\n',b'\n')
            if source.name=='device-integrations.lua':
                old=b"local ACME_STATE='/etc/acme'"
                assert body.count(old)==1
                body=body.replace(old, ("local ACME_STATE='"+remote+"/acme'").encode())
            info=tarfile.TarInfo('homepublish/files/usr/share/homepublish/'+source.name)
            info.size=len(body);tar.addfile(info,io.BytesIO(body))
        tar.add(HERE/'test-certificate-inventory.lua',arcname='inventory.lua')
        tree=ast.parse((HERE/'test-certificate-metadata.py').read_text())
        code=next(n.value.value for n in ast.walk(tree) if isinstance(n,ast.Assign) and any(isinstance(t,ast.Name) and t.id=='code' for t in n.targets))
        body=code.encode();info=tarfile.TarInfo('metadata.lua');info.size=len(body);tar.addfile(info,io.BytesIO(body))
    setup=f'umask 077; mkdir {remote} && tar -xf - -C {remote}'
    try:
        subprocess.run(ssh+[setup],input=buf.getvalue(),check=True,timeout=40)
        script=f'''set -eu
cd {remote}
openssl req -x509 -newkey rsa:2048 -nodes -days 2 -subj /CN=not-a-san.example -addext 'subjectAltName=DNS:*.example.test,DNS:example.test,DNS:xn--bcher-kva.example' -keyout key.pem -out cert.pem >/dev/null 2>&1
lua metadata.lua {remote} {remote}/cert.pem
mkdir -p 'acme/*.example.test' acme-links
cp cert.pem 'acme/*.example.test/fullchain.cer'
cp key.pem 'acme/*.example.test/*.example.test.key'
HP_ACME_STATE_DIR={remote}/acme HP_ACME_LINK_DIR={remote}/acme-links lua inventory.lua {remote}
'''
        subprocess.run(ssh+['sh -s'],input=script.encode(),check=True,timeout=60)
    finally:
        subprocess.run(ssh+[f'rm -rf {remote}; test ! -e {remote}'],check=True,timeout=25)
    print('RETAINED_CERTIFICATE_CONTRACTS_PASS; private files removed')

if __name__=='__main__':
    run()
