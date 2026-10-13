#!/usr/bin/env python3
"""Inspect real SDK ipk without installation or executing payload."""
import hashlib, io, json, pathlib, re, subprocess, tarfile
root = pathlib.Path('/home/eric/homestun-sdk-check')
sdk = root / 'openwrt-sdk-24.10.5-x86-64_gcc-13.3.0_musl.Linux-x86_64'
ipks = list(sdk.glob('bin/**/homestun_*.ipk'))
assert len(ipks) == 1, ipks
ipk = ipks[0]
with tarfile.open(ipk, 'r:gz') as outer:
    control_bytes = outer.extractfile('./control.tar.gz').read()
    payload_bytes = outer.extractfile('./data.tar.gz').read()
with tarfile.open(fileobj=io.BytesIO(control_bytes), mode='r:gz') as t:
    control = t.extractfile('./control').read().decode()
    conffiles = t.extractfile('./conffiles').read().decode()
assert 'Architecture: x86_64\n' in control
dependencies = {part.strip().split()[0] for part in next(line for line in control.splitlines() if line.startswith('Depends:')).split(':', 1)[1].split(',')}
for dep in ['libc', 'lua', 'libuci-lua', 'nginx-ssl', 'natmap', 'curl', 'ca-bundle']:
    assert dep in dependencies, dep
runtime_providers = {'libc.so': 'libc', 'libgcc_s.so.1': 'libgcc1'}
runtime_needed = {}
assert '/etc/config/homestun' in conffiles
out = root / 'inspection'
out.mkdir(exist_ok=True)
entries = []
with tarfile.open(fileobj=io.BytesIO(payload_bytes), mode='r:gz') as t:
    for m in t.getmembers():
        entries.append({'name': m.name, 'mode': oct(m.mode), 'size': m.size, 'uid':m.uid, 'gid':m.gid})
        if m.isfile():
            name = m.name.removeprefix('./')
            assert not name.startswith('/') and '..' not in pathlib.PurePosixPath(name).parts
            p = out / name
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_bytes(t.extractfile(m).read())
    names = {m.name.removeprefix('./'):m for m in t.getmembers()}
assert names['etc/homestun'].mode == 0o700
config = (out/'etc/config/homestun').read_text()
assert "option enabled '0'" in config
elf = {}
for name in ['homestun-lease', 'homestun-publish']:
    p = out/'usr/libexec'/name
    info = subprocess.check_output(['readelf','-h','-l','-d',str(p)], text=True)
    assert 'Advanced Micro Devices X86-64' in info
    assert '/lib/ld-musl-x86_64.so.1' in info
    assert 'libc.so' in info
    assert 'libc.so.6' not in info
    needed = re.findall(r'\(NEEDED\).*Shared library: \[([^\]]+)\]', info)
    assert needed, name
    for library in needed:
        assert library in runtime_providers, f'{name}: unknown runtime provider for {library}'
        assert runtime_providers[library] in dependencies, f'{name}: {library} requires explicit Depends: {runtime_providers[library]}'
    runtime_needed[name] = needed
    elf[name] = info
report = {'runtime_needed': runtime_needed, 'runtime_providers': runtime_providers, 'ipk':str(ipk),'sha256':hashlib.sha256(ipk.read_bytes()).hexdigest(),'size':ipk.stat().st_size,'control':control,'conffiles':conffiles,'payload':entries,'config':config,'elf':elf,'installed':False,'activated':False}
(root/'inspection.json').write_text(json.dumps(report,indent=2))
print(json.dumps(report,indent=2))
