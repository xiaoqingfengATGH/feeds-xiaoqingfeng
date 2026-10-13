#define _GNU_SOURCE
#include <sys/socket.h>
#include <sys/syscall.h>
#include <sys/prctl.h>
#include <linux/seccomp.h>
#include <linux/filter.h>
#include <stddef.h>
#include <netinet/in.h>
#include <unistd.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <errno.h>
#include <string.h>
static volatile sig_atomic_t done;
static void stop(int s){(void)s;done=1;}
int main(int argc,char **argv){
 if(argc>1&&!strcmp(argv[1],"deny-install")){
  struct sock_filter c[]={BPF_STMT(BPF_LD|BPF_W|BPF_ABS,offsetof(struct seccomp_data,nr)),BPF_JUMP(BPF_JMP|BPF_JEQ|BPF_K,SYS_prctl,0,3),BPF_STMT(BPF_LD|BPF_W|BPF_ABS,offsetof(struct seccomp_data,args[0])),BPF_JUMP(BPF_JMP|BPF_JEQ|BPF_K,PR_SET_SECCOMP,0,1),BPF_STMT(BPF_RET|BPF_K,SECCOMP_RET_ERRNO|EPERM),BPF_STMT(BPF_RET|BPF_K,SECCOMP_RET_ALLOW)};
  struct sock_fprog p={.len=sizeof(c)/sizeof(*c),.filter=c};
  if(prctl(PR_SET_NO_NEW_PRIVS,1,0,0,0)||prctl(PR_SET_SECCOMP,SECCOMP_MODE_FILTER,&p))return 3;
  execv(argv[2],argv+2);return 4;
 }
 if(argc>1&&!strcmp(argv[1],"occupant")){
  int fd=socket(AF_INET,SOCK_STREAM,0),one=1;setsockopt(fd,SOL_SOCKET,SO_REUSEADDR,&one,sizeof(one));
  struct sockaddr_in a={.sin_family=AF_INET,.sin_port=htons(18444),.sin_addr.s_addr=htonl(INADDR_LOOPBACK)};
  if(bind(fd,(void*)&a,sizeof(a))||listen(fd,8))return 5;
  struct sigaction sa={.sa_handler=stop};sigaction(SIGTERM,&sa,0);
  printf("OCCUPANT pid=%d fd=%d reuseport=0\n",getpid(),fd);fflush(stdout);
  while(!done){int reuse=-1;socklen_t n=sizeof(reuse);if(getsockopt(fd,SOL_SOCKET,SO_REUSEPORT,&reuse,&n)||reuse)return 6;
   int s=accept(fd,0,0);if(s<0){if(errno==EINTR)continue;return 7;}char b[16];int z=read(s,b,sizeof(b));if(z>0)write(s,b,z);close(s);
  }
  int reuse=-1;socklen_t n=sizeof(reuse);getsockopt(fd,SOL_SOCKET,SO_REUSEPORT,&reuse,&n);printf("PASS occupant final SO_REUSEPORT=%d\n",reuse);close(fd);return reuse?8:0;
 }
 if(argc>1&&!strcmp(argv[1],"echo")){
  int s=socket(AF_INET,SOCK_STREAM,0);struct sockaddr_in a={.sin_family=AF_INET,.sin_port=htons(18444),.sin_addr.s_addr=htonl(INADDR_LOOPBACK)};
  if(connect(s,(void*)&a,sizeof(a)))return 9;
  char b[16]={0};write(s,"fixture",7);if(read(s,b,16)!=7||memcmp(b,"fixture",7))return 10;puts("PASS occupant bidirectional traffic");return 0;
 }
 errno=0;long r=syscall(SYS_pidfd_getfd,-1,0,0);int e=errno;
 printf("PROBE pid=%d pidfd_getfd=%ld errno=%d no_new_privs=%d seccomp=%d\n",getpid(),r,e,prctl(PR_GET_NO_NEW_PRIVS,0,0,0,0),prctl(PR_GET_SECCOMP,0,0,0,0));fflush(stdout);
 if(argc>1&&!strcmp(argv[1],"baseline"))return !(r==-1&&e==EBADF);
 if(!(r==-1&&e==EPERM&&prctl(PR_GET_NO_NEW_PRIVS,0,0,0,0)==1&&prctl(PR_GET_SECCOMP,0,0,0,0)==2))return 11;
 FILE *o=fopen("/tmp/occupant","r");int op,of;if(!o||fscanf(o,"%d %d",&op,&of)!=2)return 13;fclose(o);
 int pd=syscall(SYS_pidfd_open,op,0);if(pd<0)return 14;errno=0;long imported=syscall(SYS_pidfd_getfd,pd,of,0);int ie=errno;close(pd);
 printf("FOREIGN pid=%d fd=%d import=%ld errno=%d\n",op,of,imported,ie);fflush(stdout);if(imported!=-1||ie!=EPERM)return 15;
 FILE *f=fopen("/tmp/probe-ready","w");if(!f)return 12;fprintf(f,"%d\n",getpid());fclose(f);
 for(;;)pause();
}
