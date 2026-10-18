import pathlib,subprocess,io,tarfile,json
repo=pathlib.Path(__file__).resolve().parents[1]
ssh=['ssh','-F','/dev/null','-i','D:/DevPortal/CloudHosts/HomePri.key','-p','222','-o','BatchMode=yes','root@127.0.0.1']
root='/tmp/homestun-luci-isolated'
def call(c,data=None):
 p=subprocess.run(ssh+[c],input=data,capture_output=True,timeout=90);print(p.stdout.decode(errors='replace'),p.stderr.decode(errors='replace'));assert p.returncode==0;return p.stdout
setup='''set -eu
R=/tmp/homestun-luci-isolated
test ! -e "$R"
mkdir -p "$R"/lib "$R"/usr/lib/lua "$R"/usr/lib/rpcd "$R"/usr/libexec/rpcd "$R"/usr/bin "$R"/usr/sbin "$R"/sbin "$R"/bin "$R"/etc/config "$R"/usr/share/rpcd/acl.d "$R"/tmp "$R"/var/run/ubus "$R"/var/state "$R"/dev "$R"/www
chmod 700 "$R"
for f in /etc/passwd /etc/group; do cp "$f" "$R$f"; done
for f in /bin/busybox /sbin/rpcd /sbin/ubusd /bin/ubus /sbin/uci /usr/bin/lua /usr/sbin/uhttpd /usr/lib/uhttpd_ubus.so /usr/lib/lua/uci.so; do cp "$f" "$R$f"; done
ln -s busybox "$R/bin/sh"
mknod "$R/dev/null" c 1 3
mknod "$R/dev/urandom" c 1 9
mount -o bind /dev/urandom "$R/dev/urandom"
for lib in /lib/*.so* /usr/lib/libjson-c.so* /usr/lib/liblua.so* /usr/lib/libubus.so* /usr/lib/libubox.so*; do [ ! -f "$lib" ] || cp -L "$lib" "$R$lib"; done
ln -s /tmp "$R/var/run/rpcd"
'''
call(setup)
files={}
for p in (repo/'luci-app-homestun/root').rglob('*'):
 if p.is_file():files[str(p.relative_to(repo/'luci-app-homestun/root')).replace('\\','/')]=p.read_bytes()
for p in (repo/'homestun/files/usr/share/homestun').glob('*.lua'):files['usr/share/homestun/'+p.name]=p.read_bytes()
files['etc/config/homestun']=(repo/'homestun/files/etc/config/homestun').read_bytes()+b"\nconfig host 'fixture'\n option name 'before.example'\n option upstream 'http://127.0.0.1:18081'\n"
# Unrelated package staged in the same session must never be committed by Save.
files['etc/config/other']=b"config fixture 'main'\n option value 'before'\n"
files['etc/config/luci']=b"config core 'main'\n"
files['etc/config/rpcd']=b"config rpcd\n option socket '/var/run/ubus/ubus.sock'\n option timeout '300'\n"
# Synthetic session grants explicit ubus calls + production package ACL; never root wildcard login.
files['usr/share/rpcd/acl.d/fixture.json']=json.dumps({'fixture':{'read':{'ubus':{'uci':['get','changes'],'session':['access']}},'write':{'ubus':{'uci':['set','add','delete','order']}}}}).encode()
buf=io.BytesIO()
with tarfile.open(fileobj=buf,mode='w:gz') as t:
 for n,b in files.items():
  a=tarfile.TarInfo(n);a.size=len(b);a.mode=0o755 if n=='usr/libexec/rpcd/homestun' else 0o644;t.addfile(a,io.BytesIO(b))
call('tar xzf - -C '+root,buf.getvalue())
call('chroot '+root+' /sbin/ubusd -s /var/run/ubus/ubus.sock >'+root+'/ubusd.log 2>&1 & echo $! >'+root+'/ubusd.pid')
call('chroot '+root+' /sbin/rpcd -s /var/run/ubus/ubus.sock >'+root+'/rpcd.log 2>&1 & echo $! >'+root+'/rpcd.pid')
call('chroot '+root+' /usr/sbin/uhttpd -f -p 127.0.0.1:18992 -h /www -u /ubus -U /var/run/ubus/ubus.sock >'+root+'/uhttpd.log 2>&1 & echo $! >'+root+'/uhttpd.pid')
print(call('chroot '+root+' /bin/ubus list').decode())
