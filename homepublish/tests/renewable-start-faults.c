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
static int failfork,calls,failpidfd;
pid_t __real_fork(void);
pid_t __wrap_fork(void) {if(++calls==failfork){errno=EAGAIN;return -1;}return __real_fork();}
long __real_syscall(long,...);
long __wrap_syscall(long n,...) {
 va_list v;va_start(v,n);
 if(n==SYS_close_range) {unsigned a=va_arg(v,unsigned),b=va_arg(v,unsigned);int c=va_arg(v,int);va_end(v);return __real_syscall(n,a,b,c);}
 int fd=va_arg(v,int);
 if(n==SYS_pidfd_open) {int flags=va_arg(v,int);va_end(v);if(failpidfd){errno=ENOSYS;return -1;}return __real_syscall(n,fd,flags);}
 int sig=va_arg(v,int);void *info=va_arg(v,void*);int flags=va_arg(v,int);va_end(v);return __real_syscall(n,fd,sig,info,flags);
}
static void child(int fd) {assert(write(fd,"started",7)==7);for(;;)poll(NULL,0,100);}
int main(int argc,char **argv) {
 assert(argc==2);assert(!prctl(PR_SET_CHILD_SUBREAPER,1));
 if(argv[1][0]=='p')failpidfd=1;else failfork=atoi(argv[1]);
 int p[2];assert(!pipe(p));struct hp_guard g;
 int rc=hp_guard_start(&g,7,9,0,child,p[1]);close(p[1]);
 struct pollfd f={p[0],POLLIN,0};assert(poll(&f,1,1000)==1);char b[10];assert(read(p[0],b,sizeof(b))==0);close(p[0]);
 for(int i=0;i<100;i++){while(waitpid(-1,NULL,WNOHANG)>0){}poll(NULL,0,10);}
 assert(waitpid(-1,NULL,WNOHANG)==-1);assert(rc==-1);
 printf("PASS startup fault %s: failure returned, callback absent, all owned PIDs absent\n",argv[1]);
}
