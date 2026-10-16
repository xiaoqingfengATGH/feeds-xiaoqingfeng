import hashlib, json, pathlib, tarfile, unittest
ROOT = pathlib.Path(__file__).resolve().parents[1]
COMMIT = 'b0e1615dec06293c927625006a99e6ec54a001aa'
ARCHIVE_HASH = 'cc247a590141120f81b1fe591d42867ae428792cfc459236431e61d6f94ad89c'
DB_HASH = '5dbb9e02471d854920e431298cfc9924b7e553fd3711b10235821a949dd80a30'
class Packaging(unittest.TestCase):
    def test_pinned_payload(self):
        self.assertTrue((ROOT/'Makefile').is_file(), 'backend package missing')
        make = (ROOT/'Makefile').read_text()
        self.assertIn(COMMIT, make)
        self.assertIn(ARCHIVE_HASH, make)
        meta = json.loads((ROOT/'files/usr/share/homekms/upstream.json').read_text())
        self.assertEqual(meta['database_sha256'], DB_HASH)
        self.assertEqual(meta['commit'], COMMIT)
        self.assertIn('KmsDataBase.xml', make)
        self.assertIn('/etc/config/homekms', make)
    def test_dynamic_service_identity(self):
        make = (ROOT/'Makefile').read_text()
        userid = next(line.split(':=', 1)[1].strip() for line in make.splitlines() if 'USERID:=' in line)
        self.assertEqual(userid, 'homekms:homekms', 'fixed IDs collide with dnsmasq=453 in the build tree')

    def test_archive(self):
        import os
        archive = os.environ.get('HOMEKMS_ARCHIVE')
        if not archive: self.skipTest('set HOMEKMS_ARCHIVE to downloaded pinned archive')
        p = pathlib.Path(archive)
        self.assertEqual(hashlib.sha256(p.read_bytes()).hexdigest(), ARCHIVE_HASH)
        with tarfile.open(p) as t:
            member = next(m for m in t.getmembers() if m.name.endswith('/py-kms/KmsDataBase.xml'))
            self.assertEqual(hashlib.sha256(t.extractfile(member).read()).hexdigest(), DB_HASH)
if __name__ == '__main__': unittest.main()
