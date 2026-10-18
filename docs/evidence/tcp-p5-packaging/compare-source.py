import tarfile, json
from pathlib import Path
w = Path('/home/eric/homestun-sdk-check/tcp-ingress-p5')
def files(path):
    with tarfile.open(path) as t:
        return {'/'.join(m.name.split('/')[1:]): t.extractfile(m).read() for m in t.getmembers() if m.isfile()}
a = files(w/'sources/nginx-1.30.6.tar.gz')
b = files(w/'sources/nginx-git-commit.tar.gz')
common = sorted(set(a) & set(b))
r = {'common_files':len(common), 'different':[p for p in common if a[p]!=b[p]], 'release_only': sorted(set(a)-set(b)), 'git_only':sorted(set(b)-set(a))}
print(json.dumps(r, indent=2))
(w/'source-compare.json').write_text(json.dumps(r, indent=2))
assert not r['different']
