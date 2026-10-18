#!/usr/bin/env python3
"""Owned WSL root chroot, genuine SDK rpcd/ubus/uhttpd + LuCI loader; never installs."""
import http.server,json,os,pathlib,shutil,subprocess,tempfile,time,urllib.request
ROOT=pathlib.Path(__file__).resolve().parents[2]
SDK=pathlib.Path('/home/eric/homestun-sdk-check/openwrt-sdk-24.10.5-x86-64_gcc-13.3.0_musl.Linux-x86_64')
TARGET=SDK/'staging_dir/target-x86_64_musl/root-x86'
OVERLAY=pathlib.Path(os.environ.get('HP_BROWSER_DEPS','/home/eric/homestun-sdk-check/homepublish-official-24.10.5/root'))
def main():
 assert os.getuid()==0,'isolated chroot needs WSL root'
 assert (OVERLAY/'usr/sbin/uhttpd').is_file(), 'missing official test-only uhttpd overlay: run fetch-browser-deps.py'
 assert (OVERLAY/'usr/lib/uhttpd_ubus.so').is_file(), 'missing official test-only uhttpd ubus module'
 with tempfile.TemporaryDirectory(prefix='rpc-luci-',dir='/home/eric/homestun-sdk-check') as td:
  d=pathlib.Path(td);procs=[];mounted=[]
  try:
   for part in ['lib','usr/lib','bin','sbin','usr/bin','usr/sbin']:
    shutil.copytree(TARGET/part,d/part,symlinks=True,dirs_exist_ok=True)
   for p in OVERLAY.rglob('*'):
    dest=d/p.relative_to(OVERLAY)
    if p.is_symlink() and (dest.exists() or dest.is_symlink()):dest.unlink()
   shutil.copytree(OVERLAY,d,symlinks=True,dirs_exist_ok=True)
   metadata=d/'ownership.json'
   metadata.write_text(json.dumps({'root':td,'wrapper_pid':os.getpid(),'ports':[18993,18994],'processes':[],'mounts':[]}))
   print('FIXTURE_ROOT '+td,flush=True)
   print(subprocess.run(['readelf','-l',str(d/'usr/sbin/uhttpd')],capture_output=True,text=True,check=True).stdout,flush=True)
   print('TARGET_LOADER',subprocess.run(['chroot',td,'/lib/ld-musl-x86_64.so.1','--list','/usr/sbin/uhttpd'],capture_output=True,text=True,check=True).stdout,flush=True)
   # SDK omits BusyBox; host dash is a fixture prerequisite, not target-shell acceptance.
   shutil.copy('/bin/dash',d/'bin/sh')
   (d/'lib/x86_64-linux-gnu').mkdir(exist_ok=True);(d/'lib64').mkdir(exist_ok=True)
   shutil.copy('/lib/x86_64-linux-gnu/libc.so.6',d/'lib/x86_64-linux-gnu/libc.so.6')
   shutil.copy('/lib64/ld-linux-x86-64.so.2',d/'lib64/ld-linux-x86-64.so.2')
   for part in ['www','tmp','var/run/ubus','etc/config','dev','usr/share/homepublish','usr/share/rpcd/acl.d','usr/libexec/rpcd']:(d/part).mkdir(parents=True,exist_ok=True)
   (d/'etc/homepublish').mkdir(mode=0o700)
   for name in ['passwd','group']:shutil.copy('/etc/'+name,d/'etc'/name)
   for name in ['null','urandom']:
    (d/'dev'/name).touch();subprocess.run(['mount','--bind','/dev/'+name,str(d/'dev'/name)],check=True);mounted.append(d/'dev'/name)
   for p in (ROOT/'homepublish/files/usr/share/homepublish').glob('*.lua'):shutil.copy(p,d/'usr/share/homepublish'/p.name)
   # Test-only metadata injection; not installed certificates or target acceptance.
   (d/'etc/config/acme').write_text("config cert 'nas'\n option domains 'nas.example.test'\n option key_type 'rsa2048'\nconfig cert 'rsa'\n option domains 'photos.example.test'\n option key_type 'rsa2048'\nconfig cert 'ecc'\n option domains 'photos.example.test'\n option key_type 'ec256'\n")
   integration=d/'usr/share/homepublish/device-integrations.lua'
   text=integration.read_text().replace('return M',"M.acme_source=function(domain,kind)return {certificate='/fixture/'..kind,key='/fixture/key',domain=domain,key_type=kind}end;require('certificate-metadata').read=function()return {sans={'photos.example.test','nas.example.test'},status='within_validity',not_before='fixture start',not_after='fixture expiry',tls_validated=false}end;return M")
   integration.write_text(text)
   shutil.copy(ROOT/'luci-app-homepublish/root/usr/libexec/rpcd/homepublish',d/'usr/libexec/rpcd/homepublish');(d/'usr/libexec/rpcd/homepublish').chmod(0o755)
   shutil.copy(ROOT/'luci-app-homepublish/root/usr/share/rpcd/acl.d/luci-app-homepublish.json',d/'usr/share/rpcd/acl.d')
   gcc=SDK/'staging_dir/toolchain-x86_64_gcc-13.3.0_musl/bin/x86_64-openwrt-linux-musl-gcc'
   subprocess.run([str(gcc),'-fPIC','-shared','-I'+str(SDK/'staging_dir/target-x86_64_musl/usr/include'),str(ROOT/'homepublish/src/product-store.c'),'-o',str(d/'usr/lib/lua/homepublish_store.so')],check=True,env={**os.environ,'STAGING_DIR':str(SDK/'staging_dir')})
   (d/'etc/config/rpcd').write_text("config rpcd\n option socket '/var/run/ubus/ubus.sock'\n option timeout '300'\n")
   def owned_metadata():
    metadata.write_text(json.dumps({'root':td,'wrapper_pid':os.getpid(),'ports':[18993,18994],'processes':[p.pid for p in procs],'mounts':[str(p) for p in mounted]}))
   def spawn(args):
    log=open(d/(args[0].split('/')[-1]+'.log'),'w');p=subprocess.Popen(['chroot',td,*args],stdout=log,stderr=log);log.close();procs.append(p);owned_metadata()
   def call(obj,method,args={}):
    p=subprocess.run(['chroot',td,'/bin/ubus','-s','/var/run/ubus/ubus.sock','call',obj,method,json.dumps(args)],capture_output=True,text=True,timeout=5)
    assert p.returncode==0,(obj,method,p.stdout,p.stderr);return json.loads(p.stdout) if p.stdout.strip() else None
   spawn(['/sbin/ubusd']);time.sleep(.3);spawn(['/sbin/rpcd']);time.sleep(.5)
   print('PLUGIN',subprocess.run(['chroot',td,'/usr/libexec/rpcd/homepublish','list'],capture_output=True,text=True),flush=True)
   print('LUA',subprocess.run(['chroot',td,'/usr/libexec/rpcd/homepublish','call','status'],input='{}',capture_output=True,text=True),flush=True)
   print('INVENTORY_DEBUG',subprocess.run(['chroot',td,'/usr/bin/lua','-e',"package.path='/usr/share/homepublish/?.lua;'..package.path;local ok,e=pcall(function()return require('device-integrations').certificate_inventory()end);print(ok,e)"],capture_output=True,text=True),flush=True)
   print('CERT_DEBUG',subprocess.run(['chroot',td,'/usr/libexec/rpcd/homepublish','call','certificates'],input='{}',capture_output=True,text=True),flush=True)
   assert call('homepublish','status')['saved_revision']==0
   sid=call('session','create',{'timeout':300})['ubus_rpc_session']
   acl=json.loads((d/'usr/share/rpcd/acl.d/luci-app-homepublish.json').read_text())['luci-app-homepublish']
   objects=[[o,m] for perm in ['read','write'] for o,methods in acl[perm]['ubus'].items() for m in methods]
   call('session','grant',{'ubus_rpc_session':sid,'scope':'ubus','objects':objects})
   call('session','set',{'ubus_rpc_session':sid,'values':{'acls':{'luci-app-homepublish':['read','write']}}})
   assert not call('session','access',{'ubus_rpc_session':sid,'scope':'ubus','object':'uci','function':'commit'})['access']
   spawn(['/usr/sbin/uhttpd','-f','-p','127.0.0.1:18994','-h','/www','-u','/ubus','-U','/var/run/ubus/ubus.sock']);time.sleep(.3)
   health=json.dumps({'jsonrpc':'2.0','id':1,'method':'call','params':[sid,'homepublish','status',{}]}).encode()
   reply=json.loads(urllib.request.urlopen(urllib.request.Request('http://127.0.0.1:18994/ubus',data=health,headers={'Content-Type':'application/json'}),timeout=5).read())
   assert reply['id']==1 and reply['result'][0]==0,reply
   print('HTTP_HEALTH',json.dumps(reply),flush=True)
   class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self,*args):pass
    def do_GET(self):
     url=self.path.split('?')[0]
     if url=='/':
      body=('''<!doctype html><html><body><div id="maincontent"><div id="view"></div></div><script>window._=s=>s;window.cbi_init=()=>{};</script><script src="/luci-static/resources/cbi.js"></script><script src="/luci-static/resources/luci.js"></script><script>
window.L=Object.create(LuCI.prototype);Object.assign(L.env,{base_url:'/luci-static/resources',resource:'/luci-static/resources',scriptname:'/cgi-bin/luci',cgi_base:'/cgi-bin',requestpath:[],documentroot:'/www',ubuspath:'/ubus',sessionid:SID,apply_display:0});L.loaded=true;window.result={};L.probeRPCBaseURL().then(()=>L.require('ui')).then(()=>L.require(location.search.includes('overview')?'view.homepublish.overview':'view.homepublish.services')).then(v=>{window.settings=v;return v.load().then(d=>v.render(d));}).then(n=>{document.querySelector('#view').appendChild(n);result.loader='PASS';}).catch(e=>{result.loader='FAIL';result.error=e.message;});
</script></body></html>''').replace('SID',json.dumps(sid)).encode()
     else:
      p=(ROOT/'luci-app-homepublish/htdocs'/url.lstrip('/')) if '/view/homepublish/' in url else TARGET/'www'/url.lstrip('/')
      if not p.is_file():self.send_error(404);return
      body=p.read_bytes()
     self.send_response(200);self.send_header('Content-Type','text/html' if url=='/' else 'text/javascript');self.end_headers();self.wfile.write(body)
    def do_POST(self):
     body=self.rfile.read(int(self.headers['Content-Length']))
     try:out=urllib.request.urlopen(urllib.request.Request('http://127.0.0.1:18994'+self.path,data=body,headers={'Content-Type':'application/json'}),timeout=6).read()
     except Exception as e:out=json.dumps({'error':str(e)}).encode()
     self.send_response(200);self.send_header('Content-Type','application/json');self.end_headers();self.wfile.write(out)
   server=http.server.ThreadingHTTPServer(('127.0.0.1',18993),Handler)
   print('READY real rpcd scoped session, denied uci.commit; real LuCI loader 18993',flush=True)
   server.serve_forever()
  finally:
   for log in d.glob('*.log'):print(log.name,log.read_text(),flush=True)
   for path in pathlib.Path('/proc').iterdir():
    if path.name.isdigit():
     try:
      if str((path/'root').readlink())==td:os.kill(int(path.name),15)
     except OSError:pass
   time.sleep(.2)
   for p in reversed(procs):
    if p.poll() is None:p.terminate()
   for p in procs:
    try:p.wait(timeout=3)
    except subprocess.TimeoutExpired:p.kill();p.wait()
   for p in reversed(mounted):subprocess.run(['umount','-l',str(p)],check=True)
   print('CLEANUP owned chroot daemons stopped and devices unmounted',flush=True)
if __name__=='__main__':
 import signal
 signal.signal(signal.SIGTERM,lambda *args: (_ for _ in ()).throw(KeyboardInterrupt()))
 main()
