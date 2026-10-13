#!/usr/bin/env python3
"""Root Linux chroot fixture: no sockets, DNS, router install or real NATMap."""
import os,pathlib,subprocess,tempfile,time,unittest,shutil
ROOT=pathlib.Path(__file__).resolve().parents[1]
class Lifecycle(unittest.TestCase):
 def test_tcp_children_expire_together(self):
  with tempfile.TemporaryDirectory(prefix='homepublish-lifecycle-') as d:
   p=pathlib.Path(d)
   for x in ('tmp/homepublish-service','usr/bin','usr/sbin'): (p/x).mkdir(parents=True)
   (p/'tmp').chmod(0o1777); r=p/'tmp/homepublish-service';r.chmod(0o700)
   for name,text in [('cert.pem','fixture'),('key.pem','fixture'),('nginx.conf','ssl_certificate /tmp/homepublish-service/cert.pem;\nssl_certificate_key /tmp/homepublish-service/key.pem;')]:
    (r/name).write_text(text);(r/name).chmod(0o600)
   c=p/'fixture.c';c.write_text('''#include <stdio.h>
#include <string.h>
#include <unistd.h>
int main(int n,char **a) {if(n>1 && !strcmp(a[1],"-t"))return 0; FILE*f=fopen("/tmp/children","a"); fprintf(f,"%s %d",a[0],getpid()); for(int i=1;i<n;i++)fprintf(f," %s",a[i]);fprintf(f,"\\n");fclose(f);for(;;)sleep(1);}
''')
   subprocess.run(['gcc','-static',str(c),'-o',str(p/'usr/bin/natmap')],check=True)
   shutil.copy(p/'usr/bin/natmap',p/'usr/sbin/nginx')
   subprocess.run(['gcc','-static','-Wall','-Wextra','-Werror',str(ROOT/'src/lease-supervisor.c'),'-o',str(p/'helper')],check=True)
   started=time.monotonic()
   result=subprocess.run(['chroot',d,'/helper','/tmp/homepublish-service','2','18444','18443','turn.cloudflare.com','example.com'],timeout=5)
   self.assertEqual(result.returncode,0,'native coordinated TCP lease not supported')
   self.assertLess(time.monotonic()-started,3.5)
   lines=(p/'tmp/children').read_text().splitlines()
   self.assertEqual(len(lines),2)
   self.assertTrue(any('natmap' in x and '-4 -b 18444 -s turn.cloudflare.com -h example.com -t 127.0.0.1 -p 18443' in x for x in lines))
   for line in lines:
    pid=int(line.split()[1]);stat=pathlib.Path(f'/proc/{pid}/stat')
    self.assertFalse(stat.exists(),f'child still exists: {pid}')
   self.assertFalse((r/'runner.lock').exists())
if __name__=='__main__':unittest.main()
