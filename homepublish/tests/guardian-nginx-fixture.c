#define _GNU_SOURCE
#include "renewable-guard.h"
#include "owned-runtime.h"
#ifdef HP_TRUST_PROFILE_HEADER
#include "trusted-nginx.h"
#endif
#include <assert.h>
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/prctl.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <sys/wait.h>
#include <unistd.h>
/* Host-test only. These paths are fixed at compilation, not executable argv. */
#ifndef HP_NGINX_LOADER
#error fixed cached loader required
#endif
extern int hp_guard_start_private_test(struct hp_guard *,uint64_t,uint64_t,unsigned,void (*)(int),int);
static struct hp_owned_runtime *runtime;
static void nginx_provider(int fd) {
 close(fd);
 if(runtime) {
  const char *names[]={"cert.pem","key.pem","nginx.conf"};
  for(unsigned i=0;i<3;i++) {
   char path[1024];snprintf(path,sizeof(path),"%s/%s",HP_NGINX_PREFIX,names[i]);
   int in=open(path,O_RDONLY|O_NOFOLLOW|O_CLOEXEC);if(in<0)_exit(127);
   char buf[65536];ssize_t n=read(in,buf,sizeof(buf));char extra;
   if(n<=0 || read(in,&extra,1)!=0 || hp_owned_file(runtime,i,buf,(size_t)n))_exit(127);
   close(in);
  }
  if(hp_owned_file(runtime,3,"",0))_exit(127);
#ifdef HP_CONTROLLER_MULTI_TEST
  const char *extra_names[]={"cert2.pem","key2.pem"};
  for(unsigned i=0;i<2;i++) {
   char path[1024];snprintf(path,sizeof(path),"%s/%s",HP_NGINX_PREFIX,extra_names[i]);
   int in=open(path,O_RDONLY|O_NOFOLLOW|O_CLOEXEC);
   if(in<0 && errno==ENOENT)continue;
   if(in<0)_exit(127);
   char buf[65536];ssize_t n=read(in,buf,sizeof(buf));char extra;
   if(n<=0 || read(in,&extra,1)!=0 || hp_owned_file(runtime,13+i,buf,(size_t)n))_exit(127);
   close(in);
  }
#endif
 }
 int log=open(HP_NGINX_PREFIX "/stderr",O_CREAT|O_APPEND|O_WRONLY,0600);
 if(log<0 || dup2(log,2)<0) _exit(127);
 #ifdef HP_TRUST_PROFILE_HEADER
 (void)hp_trusted_nginx_exec(runtime,HP_NGINX_PREFIX);dprintf(2,"trusted provider errno=%d\n",errno);_exit(127);
 #else
 char *v[]={HP_NGINX_LOADER,"--library-path",HP_NGINX_LIBS,HP_NGINX_EXEC,
            "-p",runtime?HP_NGINX_PREFIX "/runtime/":HP_NGINX_PREFIX "/","-c","nginx.conf",NULL};
 execv(v[0],v); _exit(127);
 #endif
}
static int abstract_probe;
static void private_foreign_probe(int report) {
 errno=0;assert(socket(AF_UNIX,SOCK_STREAM,0)==-1 && errno==EPERM);
 errno=0;assert(recvmsg(-1,NULL,0)==-1 && errno==EBADF);
 const char *result="private foreign socket errno=1 recvmsg errno=9\n";
 assert(write(report,result,strlen(result))==(ssize_t)strlen(result));close(report);
}
static void foreign_probe(int report) {
 int s=socket(AF_UNIX,SOCK_STREAM,0);assert(s>=0);
 struct sockaddr_un a={.sun_family=AF_UNIX};
 assert(strlen(HP_FOREIGN_SOCKET)<sizeof(a.sun_path));strcpy(a.sun_path,HP_FOREIGN_SOCKET);
 socklen_t len=sizeof(a);
 if(abstract_probe){memmove(a.sun_path+1,a.sun_path,strlen(a.sun_path));a.sun_path[0]=0;len=offsetof(struct sockaddr_un,sun_path)+1+strlen(HP_FOREIGN_SOCKET);}
 assert(!connect(s,(struct sockaddr *)&a,len));
 /* Readiness proves actual ancillary-bearing sendmsg data reached the socket.
  * Do not consume a byte with read(): that would discard SCM_RIGHTS. */
 struct pollfd ready={s,POLLIN,0};assert(poll(&ready,1,150)==1 && (ready.revents&POLLIN));
 char data[1],control[CMSG_SPACE(sizeof(int))];
 struct iovec io={data,sizeof(data)};
 struct msghdr msg={.msg_iov=&io,.msg_iovlen=1,.msg_control=control,.msg_controllen=sizeof(control)};
 errno=0;ssize_t rc=recvmsg(s,&msg,0);int e=errno;
 char result[128];int n=snprintf(result,sizeof(result),"foreign recvmsg rc=%zd errno=%d\n",rc,e);
 assert(write(report,result,n)==n);
 assert(rc==-1 && e==EPERM);close(s);close(report);
}
int main(int argc,char **argv) {
 assert(argc==3);assert(!prctl(PR_SET_CHILD_SUBREAPER,1));
 #ifdef HP_GUARD_TEST
 if(getenv("HP_TEST_INJECT_ENV")){setenv("LD_PRELOAD","/not-trusted.so",1);setenv("LD_LIBRARY_PATH","/not-trusted",1);setenv("OPENSSL_CONF","/not-trusted.cnf",1);}
 #endif
 int private_probe=!strcmp(argv[1],"private-foreign");
 abstract_probe=!strcmp(argv[1],"foreign-abstract");
 int probe=!strcmp(argv[1],"foreign") || abstract_probe || private_probe;assert(probe || !strcmp(argv[1],"nginx"));
 char *end;unsigned long temporary=strtoul(argv[2],&end,10);assert(!*end && temporary<=8000);
 if(!probe && getenv("HP_OWNED_RUNTIME")) {
  int root=open(HP_NGINX_PREFIX,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC);assert(root>=0);
  runtime=hp_owned_prepare(root);assert(runtime);close(root);hp_guard_bind_owned_test(runtime);
 }
 #ifdef HP_TRUST_PROFILE_HEADER
 if(!probe && hp_trusted_nginx_verify()) {
  if(runtime){assert(!hp_owned_cleanup(runtime));hp_owned_release(runtime);}
  printf("guard rc=-1 guardian=0\n");return 2;
 }
 #endif
 struct hp_guard g;int p[2];assert(!pipe(p));
 int rc=private_probe?hp_guard_start_private_test(&g,7,9,(unsigned)temporary,private_foreign_probe,p[1]):probe?hp_guard_start(&g,7,9,(unsigned)temporary,foreign_probe,p[1]):hp_guard_start_private_test(&g,7,9,(unsigned)temporary,nginx_provider,p[1]);close(p[1]);
 printf("guard rc=%d guardian=%d\n",rc,g.pid);fflush(stdout);if(rc)return 2;
 if(probe) {char buf[128];ssize_t n=read(p[0],buf,sizeof(buf));assert(n>0);assert(write(1,buf,n)==n);}
 close(p[0]);
 for(int i=0;i<65 && !probe;i++){if(hp_guard_send(&g,1))break;poll(NULL,0,80);}
 close(g.fd);
 for(int i=0;i<220;i++){while(waitpid(-1,NULL,WNOHANG)>0){}poll(NULL,0,5);}
 return 0;
}
