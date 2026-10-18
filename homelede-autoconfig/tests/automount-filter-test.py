
import pathlib,tempfile,subprocess,os
p=pathlib.Path(__file__).resolve().parents[1]/'files'
with tempfile.TemporaryDirectory(prefix='automount-test-',dir=os.environ.get('TMPDIR')) as d:
 r=pathlib.Path(d); (r/'bin').mkdir();entry=r/'entry';vendor=r/'vendor';filt=r/'filter'; calls=r/'calls'
 original='#!/bin/sh\nprintf "vendor:%s\\n" "$ACTION" >> "$CALLS"\n'
 entry.write_text(original)
 text=(p/'usr/libexec/homelede/automount-filter').read_text().replace('/usr/libexec/homelede/automount-vendor',str(vendor));filt.write_text(text)
 installer=(p/'usr/libexec/homelede/install-automount-filter').read_text().replace('/etc/hotplug.d/block/15-automount',str(entry)).replace('/usr/libexec/homelede/automount-vendor',str(vendor)).replace('/usr/libexec/homelede/automount-filter',str(filt))
 ins=r/'install';ins.write_text(installer)
 for f in [ins,filt]:subprocess.run(['sh','-n',str(f)],check=True)
 subprocess.run(['sh',str(ins)],check=True);assert vendor.read_text()==original;assert entry.read_text()==text
 subprocess.run(['sh',str(ins)],check=True);assert vendor.read_text()==original
 print('PASS installer install + idempotency')
 block=r/'bin/block';block.write_text('#!/bin/sh\nprintf "%s\\n" "$MOCK_INFO"\nexit "${MOCK_RC:-0}"\n');block.chmod(0o755)
 env=os.environ|{'PATH':str(r/'bin')+':'+os.environ['PATH'],'CALLS':str(calls),'DEVPATH':'/devices/block/sda/sda128'}
 cases=[('BIOS/no TYPE','add','/dev/sda128: PARTUUID="abc"',0,False),('swap','add','/dev/sdb1: TYPE="swap"',0,False),('unknown','add','',2,False),('ext4','add','/dev/sdb1: TYPE="ext4"',0,True),('exfat','add','/dev/sdb1: TYPE="exfat"',0,True),('remove','remove','',0,True),('change','change','',0,False)]
 for name,action,info,rc,want in cases:
  calls.unlink(missing_ok=True);subprocess.run(['sh',str(entry)],env=env|{'ACTION':action,'MOCK_INFO':info,'MOCK_RC':str(rc)},check=True);assert calls.exists()==want,name;print('PASS',name)
 entry.write_text(original+'# upgraded\n');subprocess.run(['sh',str(ins)],check=True);assert vendor.read_text().endswith('# upgraded\n');assert entry.read_text()==text
 print('PASS installer reconciles vendor upgrade')
