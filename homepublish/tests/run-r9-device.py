import pathlib,subprocess,json
ROOT=pathlib.Path(__file__).resolve().parents[2]
SSH=['ssh','-o','ProxyCommand=none','-o','ProxyJump=none','-o','IdentitiesOnly=yes','-o','BatchMode=yes','-i','D:/DevPortal/CloudHosts/HomePri.key','-p','222','root@127.0.0.1']
def run(cmd,stdin=None):
 p=subprocess.run(SSH+[cmd],input=stdin.encode() if stdin else None,capture_output=True,timeout=120);print(p.stdout.decode(errors='replace'));print(p.stderr.decode(errors='replace'));p.check_returncode();return p.stdout
pre="""set -eu
 e=/tmp/homepublish-r9-final-evidence
 test ! -e "$e"
 test ! -e /etc/homepublish/device-test
 test ! -e '/etc/acme/*.fixture.home'
 test ! -e '/etc/acme/*.fixture.home_ecc'
 mkdir -m 700 -p "$e"
 cp -a /etc/homepublish/product "$e/state.backup"
 cp /etc/config/acme "$e/acme.before"
 sha256sum /etc/config/firewall > "$e/firewall.before"
 netstat -lnt | sort > "$e/listeners.before"
 ip route > "$e/routes.before"
 ip -6 route > "$e/routes6.before"
"""
run('sh -s',pre)
try:
 setup=(ROOT/'homepublish/tests/router-r7-browser-setup.sh').read_text().replace('/tmp/homepublish-r7-evidence','/tmp/homepublish-r9-final-evidence')
 run('sh -s',setup)
 subprocess.run(['node',str(ROOT/'luci-app-homepublish/tests/r9-device-lifecycle.cjs')],check=True,timeout=420)
finally:
 cleanup="""set -eu
 e=/tmp/homepublish-r9-final-evidence
 ubus call homepublish stop || true
 /etc/init.d/homepublish stop || true
 /etc/init.d/homepublish disable || true
 /etc/init.d/homepublish-nginx stop || true
 /etc/init.d/homepublish-nginx disable || true
 for f in "$e/backend.pid" "$e/backend2.pid";do if test -f "$f";then p=$(cat "$f");if test -f /proc/$p/cmdline;then tr '\\0' ' ' </proc/$p/cmdline | grep "$e";kill "$p";fi;fi;done
 sleep 1
 test ! -e /tmp/homepublish-device/runtime
 rm -rf /etc/homepublish/device-test '/etc/acme/*.fixture.home' '/etc/acme/*.fixture.home_ecc'
 cp "$e/acme.before" /etc/config/acme
 rm -rf /etc/homepublish/product
 cp -a "$e/state.backup" /etc/homepublish/product
 rm -f /var/run/homepublish-controller.sock
 cmp "$e/acme.before" /etc/config/acme
 for f in "$e/state.backup/"*;do cmp "$f" "/etc/homepublish/product/${f##*/}";done
 sha256sum -c "$e/firewall.before"
 netstat -lnt | sort > "$e/listeners.after"
 cmp "$e/listeners.before" "$e/listeners.after"
 ip route > "$e/routes.after";cmp "$e/routes.before" "$e/routes.after"
 ip -6 route > "$e/routes6.after";cmp "$e/routes6.before" "$e/routes6.after"
 ! ps w | grep '[h]omepublish-controller.lua'
 test ! -e /etc/homepublish/device-test
 test ! -e '/etc/acme/*.fixture.home'
 test ! -e '/etc/acme/*.fixture.home_ecc'
 ubus call homepublish status
 echo CLEANUP_PASS
 """
 run('sh -s',cleanup)
