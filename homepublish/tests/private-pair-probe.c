#define _GNU_SOURCE
#include "renewable-guard.h"
#include <assert.h>
#include <errno.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <poll.h>
#include <signal.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/un.h>
#include <sys/wait.h>
#include <unistd.h>
/* Weak fallback exercises the old generic policy for genuine behavioral RED. */
extern int hp_guard_start_private_test(struct hp_guard *,uint64_t,uint64_t,unsigned,void (*)(int),int) __attribute__((weak));
static struct stat foreign[5];
static pid_t ancestor;
static int inherited;
static struct sockaddr_un outside,exposed;
static pid_t child_of(pid_t p){char path[128];snprintf(path,sizeof(path),"/proc/%d/task/%d/children",p,p);FILE *f=fopen(path,"r");assert(f);int child=0;assert(fscanf(f,"%d",&child)==1);fclose(f);return child;}
static void check_role(pid_t p){for(int fd=0;fd<256;fd++){char path[128];struct stat s;snprintf(path,sizeof(path),"/proc/%d/fd/%d",p,fd);if(stat(path,&s))continue;for(int i=0;i<5;i++)assert(s.st_dev!=foreign[i].st_dev || s.st_ino!=foreign[i].st_ino);}}
static void denied(int rc) {assert(rc==-1 && errno==EPERM);}
static void rights(int a,int b,int object) {
 char c='x',control[CMSG_SPACE(sizeof(int))]={0};struct iovec io={&c,1};
 struct msghdr m={.msg_iov=&io,.msg_iovlen=1,.msg_control=control,.msg_controllen=sizeof(control)};
 struct cmsghdr *h=CMSG_FIRSTHDR(&m);h->cmsg_level=SOL_SOCKET;h->cmsg_type=SCM_RIGHTS;h->cmsg_len=CMSG_LEN(sizeof(int));memcpy(CMSG_DATA(h),&object,sizeof(object));
 assert(sendmsg(a,&m,MSG_NOSIGNAL)==1);memset(control,0,sizeof(control));m.msg_controllen=sizeof(control);
 assert(recvmsg(b,&m,0)==1);h=CMSG_FIRSTHDR(&m);assert(h && h->cmsg_type==SCM_RIGHTS);int got;memcpy(&got,CMSG_DATA(h),sizeof(got));
 struct stat x,y;assert(!fstat(object,&x) && !fstat(got,&y));assert(x.st_dev==y.st_dev && x.st_ino==y.st_ino);close(got);
}
static void probe(int report) {
 /* All listening, connected, control and regular foreign objects are gone. */
 for(int fd=0;fd<256;fd++){struct stat s;if(fstat(fd,&s))continue;for(int i=0;i<5;i++)assert(s.st_dev!=foreign[i].st_dev || s.st_ino!=foreign[i].st_ino);}
 int a[2];assert(!socketpair(AF_UNIX,SOCK_STREAM,0,a));
 rights(a[0],a[1],a[0]); /* old recvmsg-deny must fail here */
 struct sockaddr unspecified={.sa_family=AF_UNSPEC};errno=0;assert(connect(a[0],&unspecified,sizeof(unspecified))==-1 && errno==EINVAL);rights(a[0],a[1],a[0]);
 int old=a[0];close(a[0]);close(a[1]);
 assert(!socketpair(AF_UNIX,SOCK_STREAM|SOCK_CLOEXEC,0,a));assert(a[0]==old);rights(a[0],a[1],a[1]);
 int d=dup(a[0]);assert(d>=0);rights(d,a[1],d);close(d);
 d=fcntl(a[0],F_DUPFD_CLOEXEC,30);assert(d>=30);rights(d,a[1],d);close(d);
 assert(dup2(a[0],40)==40);rights(40,a[1],40);close(40);
 assert(dup3(a[0],41,O_CLOEXEC)==41);rights(41,a[1],41);close(41);
 for(int domain=0;domain<64;domain++)if(domain!=AF_INET && domain!=AF_INET6){errno=0;denied(socket(domain,SOCK_STREAM,0));}
 errno=0;denied(socketpair(AF_UNIX,SOCK_DGRAM,0,(int[2]){0}));
 errno=0;denied(socketpair(AF_UNIX,SOCK_SEQPACKET,0,(int[2]){0}));
 errno=0;denied(socketpair(AF_INET,SOCK_STREAM,0,(int[2]){0}));
 errno=0;denied(syscall(SYS_pidfd_getfd,-1,0,0));
 errno=0;denied(syscall(SYS_ptrace,0,0,0,0));
 errno=0;denied(syscall(SYS_process_vm_readv,ancestor,NULL,0,NULL,0,0));
 errno=0;denied(syscall(SYS_process_vm_writev,ancestor,NULL,0,NULL,0,0));
 errno=0;denied(syscall(SYS_io_uring_setup,0,NULL));
 errno=0;denied(syscall(SYS_setns,-1,0));errno=0;denied(syscall(SYS_unshare,0));
 for(int i=0;i<2;i++){
  char path[128];snprintf(path,sizeof(path),"/proc/%s/fd/%d",i?"self":"thread-self",a[0]);errno=0;assert(open(path,O_RDWR)==-1 && errno==ENXIO);
 }
 char path[128];snprintf(path,sizeof(path),"/proc/%d/fd/%d",ancestor,inherited);errno=0;assert(open(path,O_RDWR)==-1 && errno==ENXIO);
 int pathfd=open(path,O_PATH);assert(pathfd>=0);errno=0;assert(recvmsg(pathfd,NULL,0)==-1 && errno==EBADF);int pathdup=dup(pathfd);assert(pathdup>=0);errno=0;assert(recvmsg(pathdup,NULL,0)==-1 && errno==EBADF);close(pathdup);close(pathfd);
 /* TCP sendmsg SCM_RIGHTS is not delivered as descriptor ancillary data. */
 for(int family=AF_INET;family<=AF_INET6;family+=AF_INET6-AF_INET){
  int l=socket(family,SOCK_STREAM,0);assert(l>=0);struct sockaddr_storage ss={0};socklen_t sl;
  if(family==AF_INET){struct sockaddr_in *v=(void*)&ss;v->sin_family=family;v->sin_addr.s_addr=htonl(INADDR_LOOPBACK);sl=sizeof(*v);}else{struct sockaddr_in6 *v=(void*)&ss;v->sin6_family=family;v->sin6_addr=in6addr_loopback;sl=sizeof(*v);}
  assert(!bind(l,(void*)&ss,sl) && !listen(l,1) && !getsockname(l,(void*)&ss,&sl));int s=socket(family,SOCK_STREAM,0);assert(s>=0 && !connect(s,(void*)&ss,sl));int r=accept(l,NULL,NULL);assert(r>=0);
  char c='t',ctl[CMSG_SPACE(sizeof(int))]={0};struct iovec io={&c,1};struct msghdr m={.msg_iov=&io,.msg_iovlen=1,.msg_control=ctl,.msg_controllen=sizeof(ctl)};struct cmsghdr *h=CMSG_FIRSTHDR(&m);h->cmsg_level=SOL_SOCKET;h->cmsg_type=SCM_RIGHTS;h->cmsg_len=CMSG_LEN(sizeof(int));memcpy(CMSG_DATA(h),&a[0],sizeof(int));assert(sendmsg(s,&m,0)==1);memset(ctl,0,sizeof(ctl));m.msg_controllen=sizeof(ctl);assert(recvmsg(r,&m,0)==1 && m.msg_controllen==0);close(s);close(r);close(l);
 }
 /* Naming a connected pair cannot turn it into a listener or foreign peer. */
 assert(!bind(a[0],(void*)&exposed,sizeof(exposed)));
 errno=0;assert(connect(a[0],(void*)&outside,sizeof(outside))==-1 && errno==EISCONN);
 char c='x',ctl[CMSG_SPACE(sizeof(int))]={0};struct iovec io={&c,1};struct msghdr m={.msg_name=&outside,.msg_namelen=sizeof(outside),.msg_iov=&io,.msg_iovlen=1,.msg_control=ctl,.msg_controllen=sizeof(ctl)};struct cmsghdr *h=CMSG_FIRSTHDR(&m);h->cmsg_level=SOL_SOCKET;h->cmsg_type=SCM_RIGHTS;h->cmsg_len=CMSG_LEN(sizeof(int));memcpy(CMSG_DATA(h),&a[0],sizeof(int));errno=0;assert(sendmsg(a[0],&m,0)==-1 && errno==EISCONN);
 errno=0;assert(listen(a[0],1)==-1 && errno==EINVAL);
 assert(!shutdown(a[0],SHUT_RDWR));errno=0;assert(listen(a[0],1)==-1 && errno==EINVAL);
 assert(write(report,"PRIVATE PASS\n",13)==13);poll(NULL,0,500);close(a[0]);close(a[1]);close(report);
}
int main(int argc,char **argv){
 (void)argv;
 int connected[2],control[2],l=socket(AF_UNIX,SOCK_STREAM,0),f=open("/dev/null",O_RDONLY),p[2];assert(l>=0 && f>=0 && !socketpair(AF_UNIX,SOCK_STREAM,0,connected) && !socketpair(AF_UNIX,SOCK_SEQPACKET,0,control) && !pipe(p));
 outside.sun_family=exposed.sun_family=AF_UNIX;snprintf(outside.sun_path,sizeof(outside.sun_path),"/home/eric/homestun-sdk-check/hp-foreign-%d",getpid());snprintf(exposed.sun_path,sizeof(exposed.sun_path),"/home/eric/homestun-sdk-check/hp-exposed-%d",getpid());if(argc>1)outside.sun_path[0]=exposed.sun_path[0]=0;assert(!bind(l,(void*)&outside,sizeof(outside)) && !listen(l,2));
 int foreignfd[]={l,connected[0],control[0],f,connected[1]};for(int i=0;i<5;i++)assert(!fstat(foreignfd[i],&foreign[i]));ancestor=getpid();inherited=connected[0];
 struct hp_guard g;int rc=hp_guard_start_private_test?hp_guard_start_private_test(&g,1,2,0,probe,p[1]):hp_guard_start(&g,1,2,0,probe,p[1]);assert(!rc);close(p[1]);char buf[32]={0};assert(read(p[0],buf,sizeof(buf))==13);pid_t w=child_of(g.pid),provider=child_of(w);check_role(g.pid);check_role(w);check_role(provider);
 int ext=socket(AF_UNIX,SOCK_STREAM,0);assert(ext>=0);errno=0;assert(connect(ext,(void*)&exposed,sizeof(exposed))==-1 && errno==ECONNREFUSED);close(ext);assert(write(control[0],"f",1)==1);char c;assert(read(control[1],&c,1)==1 && c=='f');for(int i=0;i<5;i++){struct stat s;assert(!fstat(foreignfd[i],&s) && s.st_ino==foreign[i].st_ino && s.st_dev==foreign[i].st_dev);}puts(buf);close(g.fd);for(int i=0;i<150;i++){while(waitpid(-1,NULL,WNOHANG)>0){}poll(NULL,0,5);}
 assert(kill(g.pid,0)==-1 && errno==ESRCH);assert(kill(w,0)==-1 && errno==ESRCH);assert(kill(provider,0)==-1 && errno==ESRCH);
 if(hp_guard_start_private_test){struct hp_guard bad;assert(hp_guard_start_private_test(&bad,1,2,0,probe,connected[0])==-1);while(waitpid(-1,NULL,WNOHANG)>0){}}
 if(argc==1){unlink(outside.sun_path);unlink(exposed.sun_path);}return 0;
}
