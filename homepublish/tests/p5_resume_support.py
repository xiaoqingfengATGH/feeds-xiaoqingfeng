import pathlib,subprocess,hashlib,json,os
R=pathlib.Path(__file__).resolve().parents[2]; E=R/'docs/evidence/tcp-p5'
SSH=['ssh','-o','ProxyCommand=none','-o','ProxyJump=none','-o','StrictHostKeyChecking=yes','-o','IdentitiesOnly=yes','-o','BatchMode=yes','-i',os.environ.get('HOMEPUBLISH_SSH_KEY','D:/DevPortal/CloudHosts/HomePri.key'),'-p',os.environ.get('HOMEPUBLISH_SSH_PORT','22'),'root@'+os.environ.get('HOMEPUBLISH_SSH_HOST','192.168.1.2')]
def remote(c,data=None):
 p=subprocess.run(SSH+[c],input=data,capture_output=True,timeout=90)
 print(p.stdout.decode(),end='');print(p.stderr.decode(),end='');p.check_returncode();return p.stdout.decode()
def upload(src,dest):
 remote('cat > '+dest,pathlib.Path(src).read_bytes())
if __name__=='__main__':
 remote('umask 077; mkdir -p /root/homepublish-p5/resume-backup; cp -p /etc/homepublish/product/state /root/homepublish-p5/resume-backup/live-state; cp -p /usr/share/homepublish/product-system-provider.lua /usr/share/homepublish/product-v2-runtime.lua /root/homepublish-p5/resume-backup/; test ! -e /usr/libexec/homepublish && echo engines-originally-absent > /root/homepublish-p5/resume-backup/engine-state; mkdir -p /usr/libexec/homepublish')
 for n,h in [('nginx','941b54d84fc4fd40b0257e42195899f0bd77895ec0486e3e263344c2fa8dc08a'),('sslh-select','1b9746f96d31624eb2cfa4076ca7eb0b636979321dbec92947171f780ee38db7')]:
  p=pathlib.Path('C:/Users/xiaoq/AppData/Local/hermes/profiles/ta/cache/scratch/p5-'+n);assert hashlib.sha256(p.read_bytes()).hexdigest()==h
  upload(p,'/usr/libexec/homepublish/'+n);remote('chmod 0755 /usr/libexec/homepublish/'+n);assert remote('sha256sum /usr/libexec/homepublish/'+n).split()[0]==h
 out=remote('/usr/libexec/homepublish/nginx -V 2>&1; /usr/libexec/homepublish/sslh-select -V 2>&1')
 (E/'resume-engine-deploy.log').write_text(out)
