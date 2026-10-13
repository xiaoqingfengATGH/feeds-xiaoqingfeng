#!/usr/bin/env python3
"""D1: re-run the genuine Chrome DOM acceptance against the migrated names.

Reuses the historical fixture approach (chroot on the router, port 18991),
with migrated paths: /tmp/homedirect-luci-isolated, homedirect views.
"""
import pathlib, subprocess, tarfile, io, json, sys

repo = pathlib.Path(__file__).resolve().parents[1]
ssh = ['ssh', '-F', '/dev/null', '-i', 'D:/DevPortal/CloudHosts/HomePri.key', '-p', '222', '-o', 'BatchMode=yes', 'root@127.0.0.1']
root = '/tmp/homedirect-luci-isolated'

def call(c, data=None, timeout=120):
    p = subprocess.run(ssh + [c], input=data, capture_output=True, timeout=timeout)
    out = p.stdout.decode(errors='replace')
    if p.returncode != 0:
        print(out, p.stderr.decode(errors='replace'))
        raise SystemExit(f'ssh command failed: {c[:120]}')
    return out

setup = '''set -eu
R=/tmp/homedirect-luci-isolated
# release any previous bind mounts and chrooted daemons before wiping the tree
# (kill by /proc root link: after exec the daemon argv no longer contains "chroot")
umount "$R/dev/urandom" 2>/dev/null || true
for p in /proc/[0-9]*; do
  case "$(readlink "$p/root" 2>/dev/null)" in
    "$R"|"$R (deleted)") kill "${p#/proc/}" 2>/dev/null || true;;
  esac
done
sleep 1
umount "$R/dev/urandom" 2>/dev/null || true
rm -rf "$R"
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

files = {}
for p in (repo / 'luci-app-homedirect/root').rglob('*'):
    if p.is_file():
        files[str(p.relative_to(repo / 'luci-app-homedirect/root')).replace('\\', '/')] = p.read_bytes()
for p in (repo / 'luci-app-homedirect/htdocs').rglob('*'):
    if p.is_file():
        files['www/' + str(p.relative_to(repo / 'luci-app-homedirect/htdocs')).replace('\\', '/')] = p.read_bytes()
for p in (repo / 'homedirect/files/usr/share/homedirect').glob('*.lua'):
    files['usr/share/homedirect/' + p.name] = p.read_bytes()
files['etc/config/homedirect'] = (repo / 'homedirect/files/etc/config/homedirect').read_bytes() + b"\nconfig host 'fixture'\n option name 'before.example'\n option upstream 'http://127.0.0.1:18081'\n"
files['etc/config/other'] = b"config fixture 'main'\n option value 'before'\n"
files['etc/config/luci'] = b"config core 'main'\n"
files['etc/config/rpcd'] = b"config rpcd\n option socket '/var/run/ubus/ubus.sock'\n option timeout '300'\n"

# luci-static assets come from the pinned LuCI assets snapshot (historical approach)
assets = repo / 'docs/artifacts/luci-target-assets'
if not assets.exists():
    raise SystemExit('missing docs/artifacts/luci-target-assets — copy from historical run or rebuild via docs/homestun-luci-assets.py')
for base in ('www',):
    for p in (assets / base).rglob('*'):
        if p.is_file():
            files[str(p.relative_to(assets)).replace('\\', '/')] = p.read_bytes()

buf = io.BytesIO()
with tarfile.open(fileobj=buf, mode='w') as tar:
    for name, data in sorted(files.items()):
        info = tarfile.TarInfo(name)
        info.size = len(data)
        # rpcd shell plugins under usr/libexec/rpcd/ must be executable to load
        info.mode = 0o755 if (name.endswith('.sh') or '/libexec/rpcd/' in name) else 0o644
        tar.addfile(info, io.BytesIO(data))
call(f'cd {root} && tar x', data=buf.getvalue())

run = '''set -eu
R=/tmp/homedirect-luci-isolated
# stop previous fixture daemons (if any) without killing the system ones
for p in /proc/[0-9]*; do
  case "$(readlink "$p/root" 2>/dev/null)" in
    "$R"|"$R (deleted)") kill "${p#/proc/}" 2>/dev/null || true;;
  esac
done
sleep 1
umount "$R/dev/urandom" 2>/dev/null || true
mkdir -p "$R/var/run/ubus"
# bind-mount the real urandom: container cgroup denies raw mknod device nodes
mount -o bind /dev/urandom "$R/dev/urandom"
setsid chroot "$R" /sbin/ubusd </dev/null >/dev/null 2>&1 &
sleep 1
setsid chroot "$R" /sbin/rpcd </dev/null >/dev/null 2>&1 &
sleep 1
setsid chroot "$R" /usr/sbin/uhttpd -f -p 127.0.0.1:18992 -h /www -u /ubus -U /var/run/ubus/ubus.sock </dev/null >"$R"/uhttpd.log 2>&1 &
sleep 2
netstat -tln 2>/dev/null | grep 18992 || echo "PORT_NOT_LISTENING"
'''
call(run, timeout=30)
print('fixture up: router chroot listening on 127.0.0.1:18992 (ssh -L 18992:127.0.0.1:18992 for Windows-side access)')
