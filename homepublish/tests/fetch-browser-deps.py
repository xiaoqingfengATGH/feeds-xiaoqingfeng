#!/usr/bin/env python3
"""Fetch release-matched official dependencies into a private test-only overlay."""
import hashlib, io, json, pathlib, tarfile, urllib.request
BASE = 'https://downloads.openwrt.org/releases/24.10.5/'
CACHE = pathlib.Path('/home/eric/homestun-sdk-check/homepublish-official-24.10.5')

def main():
    CACHE.mkdir(exist_ok=True)
    packages = {}
    indexes = []
    for feed in ['targets/x86/64/packages/', 'packages/x86_64/base/']:
        url = BASE + feed + 'Packages'
        data = urllib.request.urlopen(url, timeout=60).read()
        indexes.append({'url': url, 'sha256': hashlib.sha256(data).hexdigest()})
        for stanza in data.decode().split('\n\n'):
            fields = dict(line.split(': ', 1) for line in stanza.splitlines() if ': ' in line and not line.startswith(' '))
            if 'Package' in fields:
                packages[fields['Package']] = (feed, fields)
    overlay = CACHE / 'root'
    overlay.mkdir(exist_ok=True)
    seen = set()
    records = []
    def fetch(name):
        if name in seen:
            return
        seen.add(name)
        if name == 'libc':
            # The exact release SDK already supplies musl; do not replace its loader.
            return
        feed, fields = packages[name]
        assert fields['Architecture'] == 'x86_64', fields
        for dep in fields.get('Depends', '').split(','):
            dep = dep.strip().split(' ')[0]
            if dep:
                fetch(dep)
        url = BASE + feed + fields['Filename']
        data = urllib.request.urlopen(url, timeout=60).read()
        digest = hashlib.sha256(data).hexdigest()
        assert digest == fields['SHA256sum'], (name, digest)
        (CACHE / fields['Filename']).write_bytes(data)
        with tarfile.open(fileobj=io.BytesIO(data)) as ipk:
            member = next(m for m in ipk if m.name.endswith('data.tar.gz'))
            with tarfile.open(fileobj=ipk.extractfile(member)) as payload:
                payload.extractall(overlay, filter='fully_trusted')
        records.append({'package': name, 'version': fields['Version'], 'architecture': fields['Architecture'], 'url': url, 'sha256': digest})
    for name in ['uhttpd', 'uhttpd-mod-ubus']:
        fetch(name)
    manifest = {'release': '24.10.5', 'indexes': indexes, 'packages': records, 'overlay': str(overlay)}
    (CACHE / 'manifest.json').write_text(json.dumps(manifest, indent=2)+'\n')
    print(json.dumps(manifest, indent=2))

if __name__ == '__main__':
    main()
