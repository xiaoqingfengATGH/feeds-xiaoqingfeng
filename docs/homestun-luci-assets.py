import pathlib,subprocess,tarfile,io
repo=pathlib.Path(__file__).resolve().parents[1]
ssh=['ssh','-F','/dev/null','-i','D:/DevPortal/CloudHosts/HomePri.key','-p','222','-o','BatchMode=yes','root@127.0.0.1']
p=subprocess.run(ssh+['tar czf - /www/luci-static/resources'],capture_output=True,check=True)
dest=repo/'docs/artifacts/luci-target-assets';dest.mkdir(exist_ok=True)
with tarfile.open(fileobj=io.BytesIO(p.stdout)) as t:t.extractall(dest,filter='data')
print(dest)
