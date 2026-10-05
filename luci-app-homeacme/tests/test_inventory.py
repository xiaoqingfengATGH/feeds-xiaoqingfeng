#!/usr/bin/env python3
"""Isolated on-device integration tests. Never reads or changes live ACME config."""
import datetime,io,json,os,pathlib,tarfile,paramiko,ipaddress
from cryptography import x509
from cryptography.hazmat.primitives import hashes,serialization
from cryptography.hazmat.primitives.asymmetric import rsa,ec
from cryptography.x509.oid import NameOID
ROOT=pathlib.Path(__file__).resolve().parents[1]
REMOTE='/tmp/luci-acme-inventory-test'
def cert(key, start=-1, end=7):
 now=datetime.datetime.now(datetime.timezone.utc)
 name=x509.Name([x509.NameAttribute(NameOID.COMMON_NAME,'fixture.invalid')])
 return x509.CertificateBuilder().subject_name(name).issuer_name(name).public_key(key.public_key()).serial_number(x509.random_serial_number()).not_valid_before(now+datetime.timedelta(days=start)).not_valid_after(now+datetime.timedelta(days=end)).add_extension(x509.SubjectAlternativeName([x509.DNSName('fixture.invalid'),x509.DNSName('same.invalid'),x509.IPAddress(ipaddress.ip_address('192.0.2.1'))]),False).sign(key,hashes.SHA256()).public_bytes(serialization.Encoding.PEM)
def main():
 c=paramiko.SSHClient();c.load_system_host_keys();c.set_missing_host_key_policy(paramiko.AutoAddPolicy());c.connect(os.environ.get('ACME_TEST_HOST','192.168.224.247'),username='root',password=os.environ['ROUTER_PASSWORD'],allow_agent=False,look_for_keys=False)
 def run(cmd,data=None):
  i,o,e=c.exec_command(cmd)
  if data is not None:i.write(data);i.channel.shutdown_write()
  out=o.read().decode();err=e.read().decode();return o.channel.recv_exit_status(),out,err
 run('rm -rf '+REMOTE+'; mkdir -p '+REMOTE)
 fixtures={
 'state/fixture.invalid/fullchain.cer':cert(rsa.generate_private_key(65537,2048)),
 'state/fixture.invalid_ecc/fullchain.cer':cert(ec.generate_private_key(ec.SECP256R1()))}
 archive=io.BytesIO()
 with tarfile.open(fileobj=archive,mode='w:gz') as tf:
  for name,data in fixtures.items():
   ti=tarfile.TarInfo(name);ti.size=len(data);tf.addfile(ti,io.BytesIO(data))
 run('tar -xzf - -C '+REMOTE,archive.getvalue())
 module=ROOT/'root/usr/share/ucode/luci/acme-inventory.uc'
 if module.exists():run('cat > '+REMOTE+'/inventory.uc',module.read_bytes())
 runner='import { inventory } from "'+REMOTE+'/inventory.uc"; print(inventory("'+REMOTE+'/state", [], "'+REMOTE+'/exports"));'
 rc,out,err=run('ucode -e '+"'"+runner+"'")
 assert rc==0,'inventory not implemented or failed: '+err
 result=json.loads(out);rows=result['certificates']
 assert len(rows)==2,rows
 assert sorted(r['algorithm'] for r in rows)==['EC','RSA'],rows
 assert sorted(r['bits'] for r in rows)==[256,2048],rows
 assert all(r['status']=='valid' for r in rows),rows
 assert all(r['sans']==['fixture.invalid','same.invalid','IP Address:192.0.2.1'] for r in rows),rows
 assert len({r['id'] for r in rows})==2
 print('PASS dual algorithm / same SAN / actual key / certificate validity')
 print(json.dumps(result,indent=2))
 # A second slice exercises backend layouts, configuration association and exports.
 run('mkdir -p '+REMOTE+'/state/uacme.invalid '+REMOTE+'/exports')
 run('cat > '+REMOTE+'/state/uacme.invalid/cert.pem',cert(ec.generate_private_key(ec.SECP384R1())))
 run('ln -sf ../state/fixture.invalid_ecc/fullchain.cer '+REMOTE+'/exports/fixture.invalid.fullchain.crt')
 configs=[{'name':'rsa_one','domains':['fixture.invalid'],'key_type':'rsa2048'}, {'name':'rsa_two','domains':['fixture.invalid'],'key_type':'rsa2048'}, {'name':'ecc','domains':['fixture.invalid'],'key_type':'ec256'}, {'name':'uacme','domains':['uacme.invalid'],'key_type':'ec384'}, {'name':'missing','domains':['missing.invalid'],'key_type':'rsa4096'}]
 runner='import { inventory } from "'+REMOTE+'/inventory.uc"; print(inventory("'+REMOTE+'/state", '+json.dumps(configs)+', "'+REMOTE+'/exports"));'
 rc,out,err=run('ucode -e '+"'"+runner+"'")
 assert rc==0,err
 result=json.loads(out);rows=result['certificates']
 assert len(rows)==4,rows
 rsa_row=next(r for r in rows if r['algorithm']=='RSA')
 assert rsa_row['configurations']==['rsa_one','rsa_two'],rsa_row
 ec_row=next(r for r in rows if r['bits']==256)
 assert ec_row['exports']==[REMOTE+'/exports/fixture.invalid.fullchain.crt'],ec_row
 uacme=next(r for r in rows if r['bits']==384)
 assert uacme['algorithm']=='EC' and uacme['configurations']==['uacme'],uacme
 assert next(r for r in rows if r['configurations']==['missing'])['status']=='missing'
 print('PASS uacme EC without suffix / duplicate config / missing config / export dedup')
 key=ec.generate_private_key(ec.SECP256R1())
 extra={
 'orphan.invalid/fullchain.cer':cert(rsa.generate_private_key(65537,4096)),
 'expired.invalid/fullchain.cer':cert(key,-7,-1),
 'future.invalid/fullchain.cer':cert(key,1,7),
 'malformed.invalid/fullchain.cer':b'not a certificate SECRET_SENTINEL',
 'huge.invalid/fullchain.cer':b'x'*65537,
 'partial.invalid/partial.invalid.cer':cert(key),
 'private/excluded/fullchain.cer':cert(key),
 'accounts/fullchain.cer':cert(key),
 'ca/fullchain.cer':cert(key),
 'failed-fixture/fullchain.cer':cert(key),
 'fixture.invalid.staging/fullchain.cer':cert(key)}
 for path,data in extra.items():
  run('mkdir -p '+REMOTE+'/state/'+str(pathlib.PurePosixPath(path).parent))
  run('cat > '+REMOTE+'/state/'+path,data)
 run('ln -sf absent '+REMOTE+'/exports/broken.fullchain.crt; ln -sf loop.fullchain.crt '+REMOTE+'/exports/loop.fullchain.crt; ln -sf ../state/fixture.invalid.staging/fullchain.cer '+REMOTE+'/exports/stale.fullchain.crt')
 rc,out,err=run('ucode -e '+"'"+runner+"'")
 assert rc==0,err
 rows=json.loads(out)['certificates']
 assert not any('staging' in r['id'] or '/ca/' in r['id'] or '/accounts/' in r['id'] or '/private/' in r['id'] or 'failed-' in r['id'] for r in rows),rows
 assert next(r for r in rows if '/orphan.invalid/' in r['id'])['bits']==4096
 for name,status in [('expired','expired'),('future','not_yet_valid'),('malformed','parse_error'),('huge','parse_error')]:
  assert next(r for r in rows if '/'+name+'.invalid/' in r['id'])['status']==status
 partial=next(r for r in rows if '/partial.invalid/' in r['id'])
 assert partial['fullchain_present'] is False and partial['private_key_present'] is False,partial
 assert 'SECRET_SENTINEL' not in out and 'BEGIN ' not in out
 assert len({r['id'] for r in rows})==len(rows)
 print('PASS RSA4096 / expired / future / malformed / oversized / exclusions / broken links / partial files / no secrets')
 # Export discovery works without a state directory; missing configurations remain visible.
 fallback='import { inventory } from "'+REMOTE+'/inventory.uc"; print(inventory("'+REMOTE+'/absent", '+json.dumps(configs[-1:])+', "'+REMOTE+'/exports"));'
 rc,out,err=run('ucode -e '+"'"+fallback+"'")
 assert rc==0,err
 rows=json.loads(out)['certificates']
 assert any(r['configurations']==['missing'] for r in rows),rows
 assert any(r['algorithm']=='EC' for r in rows),rows
 print('PASS absent custom state directory / export fallback')
 # Scan and output budgets remain bounded even on oversized fixture trees.
 run('mkdir -p '+REMOTE+'/budget')
 for i in range(40):
  run('mkdir -p '+REMOTE+'/budget/cert'+str(i)+'.invalid; cp '+REMOTE+'/state/fixture.invalid/fullchain.cer '+REMOTE+'/budget/cert'+str(i)+'.invalid/fullchain.cer')
 bounded='import { inventory } from "'+REMOTE+'/inventory.uc"; print(inventory("'+REMOTE+'/budget", [], "'+REMOTE+'/none"));'
 import time
 started=time.monotonic();rc,out,err=run('ucode -e '+"'"+bounded+"'");elapsed=time.monotonic()-started
 assert rc==0,err
 result=json.loads(out)
 assert result['truncated'] and len(result['certificates'])<=32,result
 assert elapsed<6,elapsed
 print('PASS bounded scan/rows/runtime',len(result['certificates']),round(elapsed,3))
 run('rm -rf '+REMOTE)
 c.close()
if __name__=='__main__':main()
