#define _GNU_SOURCE
#include "renewable-guard.h"
#include "owned-runtime.h"
#include <assert.h>
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/prctl.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>
static struct hp_owned_runtime *r;
static int *written, calls;
static const char *mode;
static pid_t controller;
long __real_syscall(long,...);
long __wrap_syscall(long n,...) {
 va_list v;va_start(v,n);
 if(n==SYS_close_range){unsigned a=va_arg(v,unsigned),b=va_arg(v,unsigned);int c=va_arg(v,int);va_end(v);return __real_syscall(n,a,b,c);}
 if(n==SYS_capset){void *a=va_arg(v,void*),*b=va_arg(v,void*);va_end(v);return __real_syscall(n,a,b);}
 int fd=va_arg(v,int);
 if(n==SYS_pidfd_open){int f=va_arg(v,int);va_end(v);calls++;
  /* Independent review reproduction: inject EMFILE at guardian wfd open,
   * giving the old implementation a bounded opportunity to write first.
   * Not natural descriptor exhaustion. Fixed code must deny provisioning. */
  if(!strcmp(mode,"wfd") && getpid()!=controller && calls==3 && getppid()==controller){
   for(int i=0;i<150 && !*written;i++)poll(NULL,0,1);
   errno=EMFILE;return -1;
  }
  int role=getpid()==controller?0:getppid()==controller?1:2;
  if((!strcmp(mode,"pidfd-probe") && role==0 && calls==1) ||
     (!strcmp(mode,"pidfd-controller") && role==0 && calls==2) ||
     (!strcmp(mode,"pidfd-owner") && role==1 && calls==2) ||
     (!strcmp(mode,"pidfd-guardian-data") && role==1 && calls==4) ||
     (!strcmp(mode,"pidfd-watchdog-data") && role==2 && calls==3)) {errno=EMFILE;return -1;}
  return __real_syscall(n,fd,f);
 }
 int sig=va_arg(v,int);void *info=va_arg(v,void*);int f=va_arg(v,int);va_end(v);return __real_syscall(n,fd,sig,info,f);
}
int hp_guard_fault_test(const char *stage) {
 if(!strcmp(mode,stage))return -1;
 if(!strncmp(mode,"stop:",5) && !strcmp(mode+5,stage))raise(SIGSTOP);
 if(!strncmp(mode,"kill:",5) && !strcmp(mode+5,stage))raise(SIGKILL);
 if(!strcmp(mode,"after-write") && !strcmp(stage,"activated")){
  for(int i=0;i<500 && !*written;i++)poll(NULL,0,1);
  assert(*written);return -1;
 }
 return 0;
}
ssize_t __real_send(int,const void *,size_t,int);
ssize_t __wrap_send(int fd,const void *buf,size_t len,int flags) {
 if(!strcmp(mode,"short-ready") && getpid()!=controller && len==sizeof(int) && *(const int*)buf==1)
  return __real_send(fd,buf,1,flags);
 return __real_send(fd,buf,len,flags);
}
static void child(int fd){assert(!hp_owned_file(r,1,"synthetic-test-secret",21));*written=1;assert(write(fd,"R",1)==1);for(;;)pause();}
int main(int argc,char **argv){
 assert(argc==3);mode=argv[2];controller=getpid();assert(!prctl(PR_SET_CHILD_SUBREAPER,1));
 written=mmap(NULL,sizeof(int),PROT_READ|PROT_WRITE,MAP_SHARED|MAP_ANONYMOUS,-1,0);assert(written!=MAP_FAILED);
 int root=open(argv[1],O_RDONLY|O_DIRECTORY|O_CLOEXEC);assert(root>=0);r=hp_owned_prepare(root);assert(r);hp_guard_bind_owned_test(r);
 int p[2];assert(!pipe(p));struct hp_guard g;int rc=hp_guard_start(&g,7,9,0,child,p[1]);close(p[1]);if(!rc){close(g.fd);}
 for(int i=0;i<400;i++){while(waitpid(-1,NULL,WNOHANG)>0){}poll(NULL,0,5);}
 struct stat s;int residual=!fstatat(root,"runtime",&s,AT_SYMLINK_NOFOLLOW);
 printf("case=%s start_rc=%d written=%d runtime_present=%d children=%d\n",mode,rc,*written,residual,waitpid(-1,NULL,WNOHANG)!=-1);fflush(stdout);
 /* Metadata above precedes any fallback: no secret contents logged. */
 assert(rc==-1);assert(!residual);assert(waitpid(-1,NULL,WNOHANG)==-1);
 if(!strcmp(mode,"wfd"))assert(!*written);
 if(!strcmp(mode,"after-write"))assert(*written);
 hp_owned_release(r);close(root);close(p[0]);return 0;
}
