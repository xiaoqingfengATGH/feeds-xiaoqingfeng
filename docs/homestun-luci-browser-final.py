import pathlib,subprocess,json,hashlib
repo=pathlib.Path(__file__).resolve().parents[1]
ssh=['ssh','-F','/dev/null','-i','D:/DevPortal/CloudHosts/HomePri.key','-p','222','-o','BatchMode=yes','root@127.0.0.1']
cleanup=r'''set -eu
R=/tmp/homestun-luci-isolated
for p in /proc/[0-9]*; do if [ "$(readlink "$p/root")" = "$R" ]; then printf 'terminate %s ' "$p"; tr '\0' ' ' < "$p/cmdline"; printf '\n'; kill "${p##*/}"; fi; done
sleep 1
for p in /proc/[0-9]*; do if [ "$(readlink "$p/root")" = "$R" ]; then kill -9 "${p##*/}"; fi; done
if mount | busybox grep -F " on $R/dev/urandom "; then umount "$R/dev/urandom"; fi
for p in /proc/[0-9]*; do test "$(readlink "$p/root")" != "$R"; test "$(readlink "$p/cwd")" != "$R"; case "$(readlink "$p/exe")" in "$R"/*) exit 2;; esac; done
if mount | busybox grep -F "$R"; then exit 3; fi
rm -rf "$R"
test ! -e "$R"
if netstat -lntp | busybox grep -E ':18992 '; then exit 4; fi
netstat -lntp | busybox grep -E ':(22|80|443) '
printf 'PASS isolated process/root/exe/cwd, mount, tree and listener cleanup\n'
'''
# Rerun against currently owned fresh servers, always release the router fixture.
try:
 data=(repo/'homestun/files/etc/config/homestun').read_bytes()+b"\nconfig host 'fixture'\n option name 'before.example'\n option upstream 'http://127.0.0.1:18081'\n"
 subprocess.run(ssh+['test -d /tmp/homestun-luci-isolated; cat > /tmp/homestun-luci-isolated/etc/config/homestun'],input=data,check=True,timeout=30)
 subprocess.run(['python',str(repo/'docs/homestun-luci-session.py')],cwd=repo,check=True,timeout=30)
 subprocess.run(['node','luci-app-homestun/tests/persistence.cjs'],cwd=repo,check=True,timeout=75)
 evidence=json.loads((repo/'docs/artifacts/luci-browser-acceptance.json').read_text())
 for name,digest in evidence['sources'].items():assert hashlib.sha256((repo/name).read_bytes()).hexdigest()==digest,name
 print('PASS acceptance source bindings still match current files')
finally:
 p=subprocess.run(ssh+[cleanup],capture_output=True,text=True,timeout=40)
 (repo/'docs/artifacts/luci-browser-cleanup.txt').write_text(p.stdout+p.stderr)
 print(p.stdout+p.stderr)
 p.check_returncode()
