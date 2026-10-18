#define _GNU_SOURCE
#include "renewable-guard.h"
#include "owned-runtime.h"
#include <assert.h>
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>
static struct hp_owned_runtime *r;
static void child(int fd) { assert(!hp_owned_file(r,1,"owned",5));assert(write(fd,"R",1)==1);for(;;)pause(); }
int main(int argc,char **argv) {
 assert(argc==3);int root=open(argv[1],O_RDONLY|O_DIRECTORY);assert(root>=0);
 r=hp_owned_prepare(root);assert(r);hp_guard_bind_owned_test(r);
 int p[2];assert(!pipe(p));struct hp_guard g={.pid=getpid(),.fd=p[0]},before=g;
 if(!strcmp(argv[2],"foreign-replacement")) {
  int d=hp_owned_dirfd(r);assert(!unlinkat(d,"key.pem",0));
  int f=openat(d,"key.pem",O_CREAT|O_EXCL|O_WRONLY,0600);assert(f>=0);assert(write(f,"foreign",7)==7);close(f);
  struct stat a,b;assert(!fstatat(d,"key.pem",&a,0));
  assert(hp_guard_start(&g,0,9,0,child,p[1])==-1);assert(errno==ENOTRECOVERABLE);
  assert(!memcmp(&g,&before,sizeof(g)));assert(!fstatat(d,"key.pem",&b,0));assert(a.st_ino==b.st_ino && b.st_size==7);
  puts("PASS foreign replacement retained residual; invalid g untouched");
 } else {
  assert(!hp_guard_start(&g,7,9,0,child,p[1]));struct pollfd ready={p[0],POLLIN,0};assert(poll(&ready,1,500)==1);char c;assert(read(p[0],&c,1)==1);before=g;
  /* Rebinding a claimed ledger cannot acquire deletion authority. */
  hp_guard_bind_owned_test(r);
  assert(hp_guard_start(&g,0,9,0,child,p[1])==-1);assert(errno==EBUSY);assert(!memcmp(&g,&before,sizeof(g)));
  assert(hp_guard_start(&g,7,9,0,child,p[1])==-1);assert(errno==EBUSY);assert(!memcmp(&g,&before,sizeof(g)));
  /* A different prepared invocation is cleaned on EBUSY, not the active one. */
  assert(!mkdirat(root,"second",0700));int second=openat(root,"second",O_RDONLY|O_DIRECTORY);assert(second>=0);
  struct hp_owned_runtime *other=hp_owned_prepare(second);assert(other);hp_guard_bind_owned_test(other);
  assert(hp_guard_start(&g,7,9,0,child,p[1])==-1);assert(errno==EBUSY);
  struct stat s;assert(fstatat(second,"runtime",&s,0)==-1 && errno==ENOENT);hp_owned_release(other);close(second);
  assert(!fstatat(hp_owned_dirfd(r),"key.pem",&s,0));assert(s.st_size==5);assert(!kill(g.pid,0));
  assert(!hp_guard_send(&g,2));close(g.fd);assert(waitpid(g.pid,NULL,0)==g.pid);
  for(int i=0;i<100 && !fstatat(root,"runtime",&s,0);i++)poll(NULL,0,5);
  assert(fstatat(root,"runtime",&s,0)==-1 && errno==ENOENT);
  puts("PASS active reentry rejected; active ledger/PID preserved; native stop clean");
 }
 hp_owned_release(r);close(root);close(p[0]);close(p[1]);return 0;
}
