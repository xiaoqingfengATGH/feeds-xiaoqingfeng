"""Complete maps inventory. Identity trust is provider contract, not a UID sandbox."""
import pathlib, os, hashlib

def parse_maps(raw):
    rows=[]
    for line in raw.splitlines():
        f=line.split(None,5)
        assert len(f)>=5,('malformed maps',line)
        lo,hi=(int(x,16) for x in f[0].split('-'))
        major,minor=(int(x,16) for x in f[3].split(':'))
        rows.append({'start':lo,'end':hi,'permissions':f[1],'offset':int(f[2],16),
                     'device':os.makedev(major,minor),'inode':int(f[4]),
                     'path':f[5] if len(f)==6 else '', 'raw':line})
    return rows

def validate_maps(raw, expected, inspect, data_contracts):
    rows=parse_maps(raw); seen=set(); identities={}
    for row in rows:
        path=row['path']
        if not row['inode']:
            assert not path.startswith(('/', 'memfd:')),('unclassified file mapping',row)
            row['classification']='kernel-or-anonymous';continue
        # Never pre-filter by path or executable permission: readonly ELF is ELF.
        meta=inspect(row);row['identity_readback']=meta
        assert (row['device'],row['inode'])==(meta['device'],meta['inode']),('identity mismatch',row)
        if path=='/dev/zero (deleted)':
            assert meta['verified'] and not meta['elf'] and row['permissions']=='rw-s' and row['offset']==0 and row['end']-row['start']==os.sysconf('SC_PAGE_SIZE') and row['device']==os.makedev(0,1),('invalid Nginx shared anonymous zero mapping',row)
            row['classification']='musl-Nginx-one-page-shared-anonymous-zero-contract';continue
        if path in expected:
            assert meta['elf'] and meta['verified'],('unverified expected ELF',row)
            assert not ('w' in row['permissions'] and 'x' in row['permissions']),row
            old=identities.setdefault(path,(row['device'],row['inode']))
            assert old==(row['device'],row['inode']),('split object identity',row)
            seen.add(path);row['classification']='manifest-ELF'
        else:
            assert not meta['elf'] and 'x' not in row['permissions'],('unknown ELF/executable mapping',row)
            assert path in data_contracts and meta['verified'] and 'w' not in row['permissions'],('unknown data mapping',row)
            row['classification']='explicit-TZif-data-contract'
    assert seen==set(expected),('missing expected objects',set(expected)-seen)
    assert len(set(identities.values()))==len(expected),('aliased object identities',identities)
    return {'rows':rows,'objects':{k:{'device':v[0],'inode':v[1]} for k,v in identities.items()},
            'trust_scope':'native-owned provider snapshot contract; not same-UID/root isolation'}

def collect_maps(pid,runtime,sdk):
    raw=pathlib.Path('/proc',str(pid),'maps').read_text()
    names=['libpcre2-8.so.0','libssl.so.3','libcrypto.so.3','libz.so.1','libgcc_s.so.1']
    files=['usr/lib/libpcre2-8.so.0.11.2','usr/lib/libssl.so.3','usr/lib/libcrypto.so.3','usr/lib/libz.so.1.3.1','lib/libgcc_s.so.1']
    expected={str(runtime/n):sdk/f for n,f in zip(names,files)}
    expected.update({'/memfd:hp-loader (deleted)':sdk/'lib/libc.so','/memfd:hp-nginx (deleted)':sdk/'usr/sbin/nginx'})
    zone=pathlib.Path('/etc/localtime').resolve();contracts={str(zone)}
    def inspect(row):
        p=row['path']
        if p.startswith('/memfd:'):
            # CLOEXEC loader FD is gone. Read the mapped offset-zero ELF header
            # via proc mem; kernel maps dev/inode anchors all its other segments.
            first=next(x for x in parse_maps(raw) if x['path']==p and x['offset']==0)
            with open('/proc/%s/mem'%pid,'rb',buffering=0) as mem:
                mem.seek(first['start']);header=mem.read(64)
            return {'device':row['device'],'inode':row['inode'],'elf':header.startswith(b'\x7fELF'),
                    'verified':p in expected and header==expected[p].read_bytes()[:64],
                    'basis':'kernel maps identity plus mapped ELF header; provider sealed-memfd contract'}
        if p=='/dev/zero (deleted)':
            with open('/proc/%s/mem'%pid,'rb',buffering=0) as mem:
                mem.seek(row['start']);header=mem.read(4)
            return {'device':row['device'],'inode':row['inode'],'elf':header==b'\x7fELF','verified':True,'basis':'kernel shmem identity; exact musl Nginx shared anonymous zero mapping shape, mapped non-ELF header'}
        q=pathlib.Path(p);st=q.stat();data=q.read_bytes()
        verified=(p in expected and hashlib.sha256(data).digest()==hashlib.sha256(expected[p].read_bytes()).digest())
        if p in contracts:
            verified=st.st_uid==0 and not st.st_mode & 0o022 and data.startswith(b'TZif')
        return {'device':st.st_dev,'inode':st.st_ino,'elf':data.startswith(b'\x7fELF'),'verified':verified,
                'basis':'manifest SHA256 readback' if p in expected else 'exact resolved localtime root-owned non-writable TZif'}
    return raw,validate_maps(raw,expected,inspect,contracts)
