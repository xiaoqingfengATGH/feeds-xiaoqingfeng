#define _GNU_SOURCE
#include "renewable-guard.h"
#include "owned-runtime.h"
#include <assert.h>
#include <arpa/inet.h>
#include <sys/socket.h>
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
static pid_t controller; static int fork_depth;
long __real_syscall(long,...);
long __wrap_syscall(long n,...) {
 va_list v;va_start(v,n);
 if(n==SYS_close_range){unsigned a=va_arg(v,unsigned),b=va_arg(v,unsigned);int c=va_arg(v,int);va_end(v);int role=fork_depth; if((!strcmp(mode,"clean-guardian") && role==1) || (!strcmp(mode,"clean-watchdog") && role==2) || (!strcmp(mode,"clean-provider") && role==3)){errno=EIO;return -1;} return __real_syscall(n,a,b,c);}
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
 if(!strcmp(mode,"late-grant") && getpid()==controller && len==sizeof(int) && *(const int*)buf==2)poll(NULL,0,120);
 return __real_send(fd,buf,len,flags);
}
static void child(int fd){
 assert(!hp_owned_file(r,1,"synthetic-test-secret",21));
 int s=socket(AF_INET,SOCK_STREAM,0);assert(s>=0);
 struct sockaddr_in a={.sin_family=AF_INET,.sin_addr.s_addr=htonl(INADDR_LOOPBACK)};
 assert(!bind(s,(void*)&a,sizeof(a)));assert(!listen(s,2));socklen_t n=sizeof(a);assert(!getsockname(s,(void*)&a,&n));
 written[1]=ntohs(a.sin_port);*written=1;assert(write(fd,"R",1)==1);for(;;)pause();
}
int main(int argc,char **argv){
 assert(argc==3);char name[128];snprintf(name,sizeof(name),"%s",argv[2]);
 char *variant=strchr(name,'@');if(variant)*variant++=0;mode=name;controller=getpid();assert(!prctl(PR_SET_CHILD_SUBREAPER,1));
 written=mmap(NULL,2*sizeof(int),PROT_READ|PROT_WRITE,MAP_SHARED|MAP_ANONYMOUS,-1,0);assert(written!=MAP_FAILED);
 int root=open(argv[1],O_RDONLY|O_DIRECTORY|O_CLOEXEC);assert(root>=0);r=hp_owned_prepare(root);assert(r);hp_guard_bind_owned_test(r);
 struct stat foreign={0};int replaced=variant && !strcmp(variant,"foreign");
 if(variant){int d=hp_owned_dirfd(r);assert(!unlinkat(d,"key.pem",0));
  if(replaced){int f=openat(d,"key.pem",O_CREAT|O_EXCL|O_WRONLY,0600);assert(f>=0);assert(write(f,"foreign",7)==7);close(f);assert(!fstatat(d,"key.pem",&foreign,0));}}
 int p[2];assert(!pipe(p));struct hp_guard g={.pid=getpid(),.fd=p[0]};struct hp_guard untouched=g;
 int invalid=!strncmp(mode,"invalid-",8);
 int rc=hp_guard_start(!strcmp(mode,"invalid-nullguard")?NULL:&g,
  !strcmp(mode,"invalid-gen")?0:7,!strcmp(mode,"invalid-epoch")?0:9,
  !strcmp(mode,"invalid-bound")?86400001:!strcmp(mode,"late-grant")?40:0,
  !strcmp(mode,"invalid-child")?NULL:child,p[1]);
 int start_errno=errno;
 int expected=EIO;
 if(invalid)expected=EINVAL;
 if(!strcmp(mode,"pidfd-probe") || !strcmp(mode,"pidfd-controller") || !strcmp(mode,"pair-controller"))expected=EMFILE;
 if(!strcmp(mode,"fork-guardian"))expected=EAGAIN;
 if(!strcmp(mode,"map-state"))expected=ENOMEM;
 if(replaced)expected=ENOTRECOVERABLE;
 printf("case=%s errno=%d expected_errno=%d\n",argv[2],start_errno,expected);fflush(stdout);
 /* A post-grant peer death can leave provider exit unconfirmed at return,
  * even when reciprocal cleanup finishes before the later metadata snapshot. */
 int uncertain_exit=(!strcmp(mode,"kill:activated") || !strcmp(mode,"stop:activated")) && start_errno==ENOTRECOVERABLE;
 assert(start_errno==expected || uncertain_exit);
 close(p[1]);if(!rc){close(g.fd);}
 for(int i=0;i<400;i++){while(waitpid(-1,NULL,WNOHANG)>0){}poll(NULL,0,5);}
 struct stat s;int residual=!fstatat(root,"runtime",&s,AT_SYMLINK_NOFOLLOW);
 printf("case=%s start_rc=%d written=%d runtime_present=%d children=%d\n",mode,rc,*written,residual,waitpid(-1,NULL,WNOHANG)!=-1);fflush(stdout);
 /* Metadata above precedes any fallback: no secret contents logged. */
 if(written[1]) {
  int sock=socket(AF_INET,SOCK_STREAM,0);assert(sock>=0);
  struct sockaddr_in a={.sin_family=AF_INET,.sin_addr.s_addr=htonl(INADDR_LOOPBACK),.sin_port=htons(written[1])};
  assert(connect(sock,(void*)&a,sizeof(a))==-1);close(sock);
 }
 printf("listener_absent=1 recorded_port=%d\n",written[1]);
 assert(rc==-1);assert(residual==replaced);assert(waitpid(-1,NULL,WNOHANG)==-1);
 if(replaced){struct stat current;char bytes[7];int d=hp_owned_dirfd(r);assert(!fstatat(d,"key.pem",&current,0));assert(current.st_ino==foreign.st_ino && current.st_size==7);int f=openat(d,"key.pem",O_RDONLY);assert(f>=0);assert(read(f,bytes,7)==7 && !memcmp(bytes,"foreign",7));close(f);}
 if(invalid){assert(!*written);assert(!memcmp(&g,&untouched,sizeof(g)));assert(!kill(getpid(),0));}
 if(!strcmp(mode,"wfd") || !strcmp(mode,"late-grant"))assert(!*written);
 if(!strcmp(mode,"after-write"))assert(*written);
 hp_owned_release(r);close(root);close(p[0]);return 0;
}
ssize_t __real_getrandom(void*,size_t,unsigned);
ssize_t __wrap_getrandom(void *b,size_t n,unsigned f){if(!strcmp(mode,"random")){errno=EIO;return -1;}return __real_getrandom(b,n,f);}
int __real_socketpair(int,int,int,int*);
int __wrap_socketpair(int d,int t,int p,int *sv){static int c; c++;if((!strcmp(mode,"pair-controller")&&c==1)||(!strcmp(mode,"pair-guardian")&&c==2)||(!strcmp(mode,"pair-watchdog")&&c==3)){errno=EMFILE;return -1;}return __real_socketpair(d,t,p,sv);}
pid_t __real_fork(void);
pid_t __wrap_fork(void){static int c;c++;if((!strcmp(mode,"fork-guardian")&&c==1)||(!strcmp(mode,"fork-watchdog")&&c==2)||(!strcmp(mode,"fork-provider")&&c==3)){errno=EAGAIN;return -1;}pid_t r=__real_fork();if(!r)fork_depth++;return r;}
void *__real_mmap(void*,size_t,int,int,int,off_t);
void *__wrap_mmap(void*a,size_t l,int p,int f,int d,off_t o){static int c;c++;if(!strcmp(mode,"map-state")&&c==3){errno=ENOMEM;return MAP_FAILED;}return __real_mmap(a,l,p,f,d,o);}
