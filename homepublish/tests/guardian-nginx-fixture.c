#define _GNU_SOURCE
#include "renewable-guard.h"
#include <assert.h>
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/prctl.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/wait.h>
#include <unistd.h>
/* Host-test only. These paths are fixed at compilation, not executable argv. */
#ifndef HP_NGINX_LOADER
#error fixed cached loader required
#endif
static void nginx_provider(int fd) {
 close(fd);
 int log=open(HP_NGINX_PREFIX "/stderr",O_CREAT|O_APPEND|O_WRONLY,0600);
 if(log<0 || dup2(log,2)<0) _exit(127);
 char *v[]={HP_NGINX_LOADER,"--library-path",HP_NGINX_LIBS,HP_NGINX_EXEC,
            "-p",HP_NGINX_PREFIX "/","-c","nginx.conf",NULL};
 execv(v[0],v); _exit(127);
}
static void foreign_probe(int report) {
 int s=socket(AF_UNIX,SOCK_STREAM,0);assert(s>=0);
 struct sockaddr_un a={.sun_family=AF_UNIX};
 assert(strlen(HP_FOREIGN_SOCKET)<sizeof(a.sun_path));strcpy(a.sun_path,HP_FOREIGN_SOCKET);
 assert(!connect(s,(struct sockaddr *)&a,sizeof(a)));
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
 int probe=!strcmp(argv[1],"foreign");assert(probe || !strcmp(argv[1],"nginx"));
 char *end;unsigned long temporary=strtoul(argv[2],&end,10);assert(!*end && temporary<=8000);
 struct hp_guard g;int p[2];assert(!pipe(p));
 int rc=hp_guard_start(&g,7,9,(unsigned)temporary,probe?foreign_probe:nginx_provider,p[1]);close(p[1]);
 printf("guard rc=%d guardian=%d\n",rc,g.pid);fflush(stdout);if(rc)return 2;
 if(probe) {char buf[128];ssize_t n=read(p[0],buf,sizeof(buf));assert(n>0);assert(write(1,buf,n)==n);}
 close(p[0]);
 for(int i=0;i<65 && !probe;i++){if(hp_guard_send(&g,1))break;poll(NULL,0,80);}
 close(g.fd);
 for(int i=0;i<220;i++){while(waitpid(-1,NULL,WNOHANG)>0){}poll(NULL,0,5);}
 return 0;
}
