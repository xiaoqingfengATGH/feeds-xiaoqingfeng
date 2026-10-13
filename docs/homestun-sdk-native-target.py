import pathlib,subprocess,tarfile,io,hashlib,json,sys
repo=pathlib.Path(__file__).resolve().parents[1]
ssh=['ssh','-F','/dev/null','-i','D:/DevPortal/CloudHosts/HomePri.key','-p','222','-o','BatchMode=yes','-o','ConnectTimeout=10','root@127.0.0.1']
log=repo/'docs/homestun-sdk-native-target.txt'
def call(command,data=None):
 p=subprocess.run(ssh+[command],input=data,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=160)
 with log.open('ab') as f:f.write(('$ '+command+'\n').encode()+p.stdout+f'\nEXIT {p.returncode}\n'.encode())
 print(p.stdout.decode(errors='replace'));assert p.returncode==0,p.returncode
ipk=repo/'docs/artifacts/homestun_0.1.0-r1_x86_64.ipk'
assert hashlib.sha256(ipk.read_bytes()).hexdigest()=='84087e052d2cefacc7ac943ef9bc74000206379d80ca31b4de5f9c58d0ca4c22'
with tarfile.open(ipk) as t:data=t.extractfile('./data.tar.gz').read()
files={}
with tarfile.open(fileobj=io.BytesIO(data)) as t:
 for name in ['usr/libexec/homestun-lease','usr/share/homestun/config-cli.lua','usr/share/homestun/config.lua','usr/share/homestun/core.lua']:
  files['root/'+name]=t.extractfile('./'+name).read()
files['probe']=(repo/'docs/artifacts/sdk-target-probe').read_bytes()
files['run.sh']=(repo/'homestun/tests/router-sdk-native.sh').read_bytes()
buf=io.BytesIO()
with tarfile.open(fileobj=buf,mode='w:gz') as t:
 for name,data in files.items():
  m=tarfile.TarInfo(name);m.size=len(data);m.mode=0o700;t.addfile(m,io.BytesIO(data))
manifest={name:hashlib.sha256(data).hexdigest() for name,data in files.items()}
(repo/'docs/homestun-sdk-native-hashes.json').write_text(json.dumps(manifest,indent=2))
call('test ! -e /tmp/homestun-test/sdk-native && mkdir -p /tmp/homestun-test/sdk-native && chmod 700 /tmp/homestun-test /tmp/homestun-test/sdk-native && tar xzf - -C /tmp/homestun-test/sdk-native',buf.getvalue())
checks='\n'.join(f'{h}  /tmp/homestun-test/sdk-native/{n}' for n,h in manifest.items())+'\n'
call('sha256sum -c -',checks.encode())
call('timeout 140 sh /tmp/homestun-test/sdk-native/run.sh')
