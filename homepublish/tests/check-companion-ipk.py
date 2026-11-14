#!/usr/bin/env python3
"""Check actual LuCI and engine IPKs without installation or extraction."""
import argparse
import hashlib
import io
import json
from pathlib import Path
import tarfile
ROOT = Path(__file__).resolve().parents[2]

def inspect(path):
    with tarfile.open(path) as outer:
        def nested(name):
            m = next(m for m in outer.getmembers() if m.name.removeprefix('./') == name)
            return tarfile.open(fileobj=io.BytesIO(outer.extractfile(m).read()))
        with nested('data.tar.gz') as data, nested('control.tar.gz') as control:
            files = {m.name.removeprefix('./'): (m.mode, data.extractfile(m).read()) for m in data if m.isfile()}
            meta = next(control.extractfile(m).read().decode() for m in control if m.name.removeprefix('./') == 'control')
    meta = dict(line.split(': ', 1) for line in meta.splitlines() if ': ' in line)
    name = meta['Package']
    assert not any('__pycache__' in k or k.startswith('tests/') or '/tests/' in k for k in files)
    if name == 'luci-app-homepublish':
        assert {'homepublish','luci-base'} <= set(meta['Depends'].split(', '))
        mode, _ = files['usr/libexec/rpcd/homepublish']
        assert mode & 0o111 and not mode & 0o002
        for key in ('usr/share/luci/menu.d/luci-app-homepublish.json','usr/share/rpcd/acl.d/luci-app-homepublish.json'):
            assert isinstance(json.loads(files[key][1]), dict)
            assert not files[key][0] & 0o002
        for directory, prefix in (('htdocs', 'www'), ('root', '')):
            base = ROOT/name/directory
            for source in base.rglob('*'):
                if source.is_file():
                    key = '/'.join(filter(None, (prefix, source.relative_to(base).as_posix())))
                    assert files[key][1] == source.read_bytes().replace(b'\r\n', b'\n'), 'stale payload: '+key
    else:
        assert name == 'homepublish-engines', name
        assert {'libc', 'libopenssl3', 'libpcre2', 'zlib', 'libcap'} <= set(meta['Depends'].split(', '))
        for binary in ('nginx', 'sslh-select'):
            mode, body = files['usr/libexec/homepublish/'+binary]
            assert mode & 0o111 and not mode & 0o002
            assert body[:4] == b'\x7fELF', binary
            if meta['Architecture'] == 'x86_64':
                assert body[4:6] == b'\x02\x01' and int.from_bytes(body[18:20], 'little') == 62
    print('COMPANION_IPK_PASS', name, meta['Version'], hashlib.sha256(path.read_bytes()).hexdigest(), 'files', len(files))
    return name

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('ipk', type=Path, nargs='+')
    parser.add_argument('--complete', action='store_true')
    args = parser.parse_args()
    names = {inspect(artifact) for artifact in args.ipk}
    if args.complete:
        assert names == {'luci-app-homepublish','homepublish-engines'}, names
    print('NOTE: archive/ELF checks do not prove target ABI or package failure rollback.')
