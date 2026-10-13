#define _GNU_SOURCE
#include "renewable-guard.h"
#include <assert.h>
#include <errno.h>
#include <poll.h>
#include <stdarg.h>
#include <stdlib.h>
#include <stdio.h>
#include <sys/prctl.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>
#include <signal.h>
#include <string.h>
#include <sys/mman.h>
#include <time.h>
static int suspendfork, killsignal;
static pid_t *owned;
static long long ms(void) {struct timespec t;assert(!clock_gettime(CLOCK_MONOTONIC,&t));return (long long)t.tv_sec*1000+t.tv_nsec/1000000;}
static int failfork,calls,failpidfd;
pid_t __real_fork(void);
pid_t __wrap_fork(void) {
 if(++calls==failfork){errno=EAGAIN;return -1;}
 pid_t p=__real_fork();
 if(!p) {owned[calls-1]=getpid();if(calls==suspendfork) raise(killsignal?SIGKILL:SIGSTOP);}
 return p;
}
long __real_syscall(long,...);
long __wrap_syscall(long n,...) {
 va_list v;va_start(v,n);
 if(n==SYS_close_range) {unsigned a=va_arg(v,unsigned),b=va_arg(v,unsigned);int c=va_arg(v,int);va_end(v);return __real_syscall(n,a,b,c);}
 if(n==SYS_capset) {void *a=va_arg(v,void*),*b=va_arg(v,void*);va_end(v);return __real_syscall(n,a,b);}
 int fd=va_arg(v,int);
 if(n==SYS_pidfd_open) {int flags=va_arg(v,int);va_end(v);if(failpidfd){errno=ENOSYS;return -1;}return __real_syscall(n,fd,flags);}
 int sig=va_arg(v,int);void *info=va_arg(v,void*);int flags=va_arg(v,int);va_end(v);return __real_syscall(n,fd,sig,info,flags);
}
static void child(int fd) {assert(write(fd,"started",7)==7);for(;;)poll(NULL,0,100);}
int main(int argc,char **argv) {
 assert(argc==2);assert(!prctl(PR_SET_CHILD_SUBREAPER,1));
 owned=mmap(NULL,3*sizeof(pid_t),PROT_READ|PROT_WRITE,MAP_SHARED|MAP_ANONYMOUS,-1,0);assert(owned!=MAP_FAILED);
 if(!strncmp(argv[1],"stop",4) || !strncmp(argv[1],"kill",4)) {suspendfork=atoi(argv[1]+4);killsignal=argv[1][0]=='k';}
 else if(argv[1][0]=='p')failpidfd=1;else failfork=atoi(argv[1]);
 int p[2];assert(!pipe(p));struct hp_guard g;
 long long started=ms();int rc=hp_guard_start(&g,7,9,0,child,p[1]);close(p[1]);
 if(suspendfork) {
  for(int i=0;i<100;i++){while(waitpid(-1,NULL,WNOHANG)>0){}poll(NULL,0,5);}
  int residual=0;for(int i=0;i<3;i++) if(owned[i]>0 && !kill(owned[i],0))residual++;
  for(int i=0;i<3;i++) if(owned[i]>0) {kill(-owned[i],SIGKILL);kill(owned[i],SIGKILL);}
  for(int i=0;i<100;i++){while(waitpid(-1,NULL,WNOHANG)>0){}poll(NULL,0,5);}
  printf("startup %s: rc=%d residual-before-fallback=%d elapsed=%lldms\n",argv[1],rc,residual,ms()-started);fflush(stdout);
  assert(!residual);assert(rc==-1);assert(ms()-started<2200);assert(waitpid(-1,NULL,WNOHANG)==-1);close(p[0]);return 0;
 }
 struct pollfd f={p[0],POLLIN,0};assert(poll(&f,1,1000)==1);char b[10];assert(read(p[0],b,sizeof(b))==0);close(p[0]);
 for(int i=0;i<100;i++){while(waitpid(-1,NULL,WNOHANG)>0){}poll(NULL,0,10);}
 assert(waitpid(-1,NULL,WNOHANG)==-1);assert(rc==-1);
 printf("PASS startup fault %s: failure returned, callback absent, all owned PIDs absent\n",argv[1]);
}
