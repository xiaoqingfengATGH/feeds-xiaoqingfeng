#define _GNU_SOURCE
#include "renewable-guard.h"
#include <assert.h>
#include <arpa/inet.h>
#include <errno.h>
#include <poll.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/prctl.h>
#include <sys/socket.h>
#include <sys/wait.h>
#include <unistd.h>
#include <sys/syscall.h>
#include <linux/sched.h>
static const char *mode;
static pid_t foreign_group;
struct report {pid_t pid; unsigned port; int escape, nnp, seccomp, death;};
static void worker(int fd) {
 int escape=0;
 if(!strcmp(mode,"setsid") || !strncmp(mode,"exec",4)) escape=setsid()>=0;
 if(!strcmp(mode,"boundary")) {
  assert(syscall(SYS_unshare,CLONE_NEWUSER)==-1 && errno==EPERM);
  assert(syscall(SYS_setns,-1,0)==-1 && errno==EPERM);
  assert(syscall(SYS_clone,CLONE_NEWUSER|SIGCHLD,NULL,NULL,NULL,0)==-1 && errno==EPERM);
  assert(syscall(SYS_clone3,NULL,0)==-1 && errno==ENOSYS);
  assert(syscall(SYS_pidfd_getfd,-1,0,0)==-1 && errno==EPERM);
  assert(syscall(SYS_ptrace,0,0,NULL,NULL)==-1 && errno==EPERM);
  assert(syscall(SYS_process_vm_readv,0,NULL,0,NULL,0,0)==-1 && errno==EPERM);
  assert(syscall(SYS_process_vm_writev,0,NULL,0,NULL,0,0)==-1 && errno==EPERM);
  assert(recvmsg(-1,NULL,0)==-1 && errno==EPERM);
  assert(setuid(getuid())==-1 && errno==EPERM);
 }
 if(!strcmp(mode,"setpgid")) escape=setpgid(0,0)==0;
 if(!strcmp(mode,"foreigngroup")) escape=setpgid(0,foreign_group)==0;
 int s=socket(AF_INET,SOCK_STREAM,0);assert(s>=0);
 struct sockaddr_in a={.sin_family=AF_INET,.sin_addr.s_addr=htonl(INADDR_LOOPBACK)};
 assert(!bind(s,(void*)&a,sizeof(a)));assert(!listen(s,4));socklen_t n=sizeof(a);assert(!getsockname(s,(void*)&a,&n));
 int death=0;assert(!prctl(PR_GET_PDEATHSIG,&death));
 struct report r={getpid(),ntohs(a.sin_port),escape,prctl(PR_GET_NO_NEW_PRIVS,0,0,0,0),prctl(PR_GET_SECCOMP),death};
 assert(write(fd,&r,sizeof(r))==sizeof(r));close(fd);
 int c=accept(s,NULL,NULL);assert(c>=0);
 for(;;) {if(send(c,"tick\n",5,MSG_NOSIGNAL)<0) _exit(0);poll(NULL,0,20);}
}
static void provider(int fd) {
 if(!strcmp(mode,"exec-leader")) {char arg[32];snprintf(arg,sizeof(arg),"%d",fd);execl("/proc/self/exe","fixture","exec-worker",arg,NULL);_exit(127);}
 pid_t p=fork();assert(p>=0);if(p) {close(fd);for(;;)poll(NULL,0,100); }
 if(!strncmp(mode,"doublefork",10)) {p=fork();assert(p>=0);if(p)_exit(0);poll(NULL,0,50);}
 if(!strncmp(mode,"exec",4)) {char arg[32];snprintf(arg,sizeof(arg),"%d",fd);execl("/proc/self/exe","fixture","exec-worker",arg,NULL);_exit(127);}
 worker(fd);
}
static int conn(unsigned port) {
 int s=socket(AF_INET,SOCK_STREAM,0);assert(s>=0);struct sockaddr_in a={.sin_family=AF_INET,.sin_addr.s_addr=htonl(INADDR_LOOPBACK),.sin_port=htons(port)};
 if(connect(s,(void*)&a,sizeof(a))) {close(s);return -1;}return s;
}
static pid_t childof(pid_t p) {
 char path[100];snprintf(path,sizeof(path),"/proc/%d/task/%d/children",p,p);FILE *f=fopen(path,"r");assert(f);int c=0;assert(fscanf(f,"%d",&c)==1);fclose(f);return c;
}
int main(int argc,char **argv) {
 if(argc==3 && !strcmp(argv[1],"exec-worker")) {mode="exec";worker(atoi(argv[2]));return 0;}
 assert(argc==2);mode=argv[1];assert(!prctl(PR_SET_CHILD_SUBREAPER,1));
 foreign_group=getpgrp();int p[2];assert(!pipe(p));struct hp_guard g;
 assert(!hp_guard_start(&g,7,9,0,provider,p[1]));close(p[1]);
 struct report r;struct pollfd f={p[0],POLLIN,0};assert(poll(&f,1,1000)==1);assert(read(p[0],&r,sizeof(r))==sizeof(r));close(p[0]);
 pid_t watchdog=childof(g.pid),leader=childof(watchdog);
 assert(r.death==(!strcmp(mode,"exec-leader")?SIGKILL:0));
 int s=conn(r.port);assert(s>=0);char buf[1024];assert(recv(s,buf,sizeof(buf),0)>0);
 if(strstr(mode,"guardian-kill"))assert(!kill(g.pid,SIGKILL));
 if(strstr(mode,"guardian-stop"))assert(!kill(g.pid,SIGSTOP));
 if(strstr(mode,"watchdog-kill"))assert(!kill(watchdog,SIGKILL));
 if(strstr(mode,"watchdog-stop"))assert(!kill(watchdog,SIGSTOP));
 poll(NULL,0,strstr(mode,"-kill") || strstr(mode,"-stop")?350:850);
 int t=conn(r.port),closed=t<0;if(t>=0)close(t);
 for(int i=0;i<100;i++){while(waitpid(-1,NULL,WNOHANG)>0){}poll(NULL,0,5);}
 int residual=0;pid_t ids[]={r.pid,leader,watchdog,g.pid};
 for(unsigned i=0;i<sizeof(ids)/sizeof(ids[0]);i++)if(!kill(ids[i],0))residual++;
 while(recv(s,buf,sizeof(buf),MSG_DONTWAIT)>0) {}
 int eof=recv(s,buf,sizeof(buf),MSG_DONTWAIT)==0;
 /* Always clean a RED escape before asserting, never leak a failing listener. */
 close(g.fd);kill(r.pid,SIGKILL);kill(-leader,SIGKILL);kill(leader,SIGKILL);kill(watchdog,SIGKILL);kill(g.pid,SIGKILL);close(s);
 for(int i=0;i<100;i++) {while(waitpid(-1,NULL,WNOHANG)>0){}poll(NULL,0,5);}
 assert(waitpid(-1,NULL,WNOHANG)==-1);
 assert(kill(r.pid,0)<0 && errno==ESRCH);assert(kill(leader,0)<0 && errno==ESRCH);assert(kill(watchdog,0)<0 && errno==ESRCH);assert(kill(g.pid,0)<0 && errno==ESRCH);
 printf("tree %s: escape=%d closed=%d nnp=%d seccomp=%d exec/fork PDEATHSIG=%d all PIDs absent\n",mode,r.escape,closed,r.nnp,r.seccomp,r.death);fflush(stdout);
 assert(!r.escape);assert(closed);assert(eof);assert(!residual);assert(r.nnp==1 && r.seccomp==2);
 return 0;
}
