#!/usr/bin/env python3
"""Root WSL/Linux only; run in an isolated network namespace, never on router."""
import os, pathlib, shutil, socket, subprocess, tempfile, time, unittest
if os.geteuid() != 0:
 raise SystemExit('run as root in an isolated WSL/Linux network namespace')
if os.readlink('/proc/self/ns/net') == os.readlink('/proc/1/ns/net'):
 raise SystemExit('refusing sockets in the host network namespace; use unshare -n')
ROOT = pathlib.Path(__file__).resolve().parents[1]

PROBE = r'''
#define _GNU_SOURCE
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/socket.h>
#include <sys/syscall.h>
#include <netinet/in.h>
int main(int argc, char **argv) {
 if (argc > 1 && !strcmp(argv[1], "-t")) return 0;
 if (!strcmp(argv[0], "nginx")) { FILE *n=fopen("/tmp/nginx-started","w"); fclose(n); for (;;) pause(); }
 FILE *f = fopen("/tmp/probe", "w");
 errno = 0; long res = syscall(SYS_pidfd_getfd, -1, -1, 0);
 fprintf(f, "%ld %d\n", res, errno); fclose(f);
 return 1;
}
'''

SOCKET_PROBE = r'''
#include "hev-misc.c"
#include <errno.h>
#include <string.h>
#include <arpa/inet.h>
int main(int argc, char **argv) {
 if(argc>1 && !strcmp(argv[1],"-t")) return 0;
 if(!strcmp(argv[0],"nginx")) {for(;;)pause();}
 int fd=socket(AF_INET,SOCK_STREAM,0),one=1;
 setsockopt(fd,SOL_SOCKET,SO_REUSEADDR,&one,sizeof one);
 setsockopt(fd,SOL_SOCKET,SO_REUSEPORT,&one,sizeof one);
 struct sockaddr_in addr={.sin_family=AF_INET,.sin_addr.s_addr=htonl(INADDR_LOOPBACK),.sin_port=htons(atoi(argv[3]))};
 if(getenv("RACE")) {
  if(bind(fd,(void*)&addr,sizeof addr)) return 4;
  close(fd); /* Simulates a successful preflight followed by a losing startup race. */
  FILE*f=fopen("/tmp/ready","w");fclose(f);
  while(access("/tmp/go",F_OK)) usleep(1000);
  fd=socket(AF_INET,SOCK_STREAM,0);
  setsockopt(fd,SOL_SOCKET,SO_REUSEADDR,&one,sizeof one);
  setsockopt(fd,SOL_SOCKET,SO_REUSEPORT,&one,sizeof one);
 }
 if(bind(fd,(void*)&addr,sizeof addr)==0) return 5;
 errno=0;
 int res=set_reuse_port(atoi(getenv("VICTIM_PID")),atoi(getenv("VICTIM_FD")));
 int saved=errno;
 FILE*f=fopen("/tmp/fallback","w");fprintf(f,"%d %d\n",res,saved);fclose(f);
 if(bind(fd,(void*)&addr,sizeof addr)==0) {listen(fd,5);return 6;}
 return 2;
}
'''

class Boundary(unittest.TestCase):
 def setUp(self):
  self.tmp = tempfile.TemporaryDirectory(prefix='homedirect-boundary-')
  self.p = pathlib.Path(self.tmp.name)
  for name in ('tmp/homedirect-security', 'usr/bin', 'usr/sbin'):
   (self.p/name).mkdir(parents=True)
  (self.p/'tmp').chmod(0o1777)
  self.runtime = self.p/'tmp/homedirect-security'; self.runtime.chmod(0o700)
  for name, data in [('cert.pem','fixture'), ('key.pem','fixture'), ('nginx.conf',
   'ssl_certificate /tmp/homedirect-security/cert.pem;\nssl_certificate_key /tmp/homedirect-security/key.pem;')]:
   (self.runtime/name).write_text(data); (self.runtime/name).chmod(0o600)
  subprocess.run(['gcc','-static','-Wall','-Wextra','-Werror',str(ROOT/'src/lease-supervisor.c'),'-o',str(self.p/'helper')],check=True)
  self.build(PROBE)
 def tearDown(self): self.tmp.cleanup()
 def build(self, text):
  (self.p/'probe.c').write_text(text)
  subprocess.run(['gcc','-static',str(self.p/'probe.c'),'-o',str(self.p/'usr/bin/natmap')],check=True)
  shutil.copy(self.p/'usr/bin/natmap',self.p/'usr/sbin/nginx')
 def command(self, port='18444'):
  return ['chroot',str(self.p),'/helper','/tmp/homedirect-security','4',port,'18443','127.0.0.1','127.0.0.1']
 def test_pidfd_getfd_denied_before_engine_exec(self):
  result = subprocess.run(self.command(),timeout=6)
  self.assertNotEqual(result.returncode,0)
  self.assertEqual((self.p/'tmp/probe').read_text().strip(),'-1 1',
   'pidfd_getfd must return EPERM from installed seccomp, not EBADF/ENOSYS')
  self.assertFalse((self.runtime/'runner.lock').exists())

 def occupied(self, race):
  upstream = pathlib.Path(os.environ['NATMAP_SOURCE'])
  revision = subprocess.check_output(['git','-c',f'safe.directory={upstream}','-C',str(upstream),'rev-parse','HEAD'],text=True).strip()
  self.assertEqual(revision,'f8d7996710677c9885c148dda80a42d626f0a17b')
  (self.p/'socket.c').write_text(SOCKET_PROBE)
  subprocess.run(['gcc','-static','-ffunction-sections','-Wl,--gc-sections','-I'+str(upstream/'src'),'-I'+str(upstream/'third-part/hev-task-system/include'),str(self.p/'socket.c'),'-o',str(self.p/'usr/bin/natmap')],check=True)
  # Negative control compiles a scratch copy without the boundary, never edits production.
  if os.environ.get('HOMEDIRECT_SECURITY_NEGATIVE_CONTROL') == '1':
   source = (ROOT/'src/lease-supervisor.c').read_text().replace('if(confine_natmap())','if(0)')
   (self.p/'unconfined.c').write_text(source)
   subprocess.run(['gcc','-static',str(self.p/'unconfined.c'),'-o',str(self.p/'helper')],check=True)
  with socket.socket() as victim:
   victim.setsockopt(socket.SOL_SOCKET,socket.SO_REUSEADDR,1)
   victim.bind(('127.0.0.1',0)); port=victim.getsockname()[1]
   if not race: victim.listen(8)
   else:
    victim.close()
    victim=socket.socket();victim.setsockopt(socket.SOL_SOCKET,socket.SO_REUSEADDR,1)
   env=dict(os.environ,VICTIM_PID=str(os.getpid()),VICTIM_FD=str(victim.fileno()))
   if race: env['RACE']='1'
   proc=subprocess.Popen(self.command(str(port)),env=env)
   try:
    if race:
     deadline=time.monotonic()+2
     while not (self.p/'tmp/ready').exists() and time.monotonic()<deadline: time.sleep(.005)
     self.assertTrue((self.p/'tmp/ready').exists(),'engine did not reach startup race gate')
     victim.bind(('127.0.0.1',port));victim.listen(8)
     (self.p/'tmp/go').write_text('go')
    self.assertNotEqual(proc.wait(timeout=6),0,'busy port must fail closed')
    self.assertEqual(victim.getsockopt(socket.SOL_SOCKET,socket.SO_REUSEPORT),0,'foreign socket mutated')
    self.assertEqual((self.p/'tmp/fallback').read_text().strip(),'-1 1','upstream descriptor import was not denied')
    with socket.create_connection(('127.0.0.1',port),timeout=1) as client:
     conn,_=victim.accept()
     with conn:
      client.sendall(b'normal traffic');self.assertEqual(conn.recv(64),b'normal traffic')
      conn.sendall(b'preserved');self.assertEqual(client.recv(64),b'preserved')
    self.assertFalse((self.runtime/'runner.lock').exists())
   finally:
    if proc.poll() is None: proc.kill();proc.wait(timeout=6)
    victim.close()
 def test_occupied_port_preserves_foreign_socket_and_traffic(self): self.occupied(False)
 def test_startup_race_preserves_foreign_socket_and_traffic(self): self.occupied(True)

 def test_unavailable_seccomp_never_executes_engines(self):
  fault = self.p/'fault.c'
  fault.write_text(r'''
#define _GNU_SOURCE
#include <errno.h>
#include <stdarg.h>
#include <sys/prctl.h>
#include <sys/syscall.h>
#include <unistd.h>
int __wrap_prctl(int op, ...) {
 va_list ap; va_start(ap, op);
 if(op == PR_SET_SECCOMP) { usleep(100000); va_end(ap); errno=EINVAL; return -1; }
 if(op == PR_SET_NO_NEW_PRIVS) {va_end(ap); return syscall(SYS_prctl,op,1,0,0,0);}
 int value=va_arg(ap,int); va_end(ap);
 return syscall(SYS_prctl,op,value,0,0,0);
}
''')
  subprocess.run(['gcc','-static','-Wall','-Wextra','-Werror',str(ROOT/'src/lease-supervisor.c'),str(fault),'-Wl,--wrap=prctl','-o',str(self.p/'helper')],check=True)
  result = subprocess.run(self.command(),timeout=6)
  self.assertNotEqual(result.returncode,0)
  self.assertFalse((self.p/'tmp/probe').exists(),'NATMap executed without boundary')
  self.assertFalse((self.p/'tmp/nginx-started').exists(),'listener executed before boundary established')
  self.assertFalse((self.runtime/'runner.lock').exists())

if __name__ == '__main__': unittest.main()
