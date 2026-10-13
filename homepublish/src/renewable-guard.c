#define _GNU_SOURCE
#include "renewable-guard.h"
#include <errno.h>
#include <poll.h>
#include <signal.h>
#include <string.h>
#include <sys/prctl.h>
#include <sys/random.h>
#include <sys/socket.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
/* Fail closed without close_range: never rely on CLOEXEC for fork callbacks. */
static int clean_fds(int a,int b,int c) {
 int keep[3]={a,b,c};
 for(int i=0;i<3;i++) for(int j=i+1;j<3;j++) if(keep[j]<keep[i]) {int t=keep[i];keep[i]=keep[j];keep[j]=t;}
 unsigned first=0;
 for(int i=0;i<3;i++) {
  if(keep[i]<0 || (unsigned)keep[i]<first) continue;
  if((unsigned)keep[i]>first && syscall(SYS_close_range,first,(unsigned)keep[i]-1,0)) return -1;
  first=(unsigned)keep[i]+1;
 }
 return syscall(SYS_close_range,first,~0U,0);
}
static int64_t now_ms(void) {
 struct timespec t;
 if(clock_gettime(CLOCK_MONOTONIC,&t)) _exit(125);
 return (int64_t)t.tv_sec*1000+t.tv_nsec/1000000;
}
int hp_guard_send(struct hp_guard *g, uint32_t op) {
 struct hp_frame f={.generation=g->generation,.epoch=g->epoch,.sequence=++g->sequence,.operation=op};
 memcpy(f.token,g->token,16);
 return send(g->fd,&f,sizeof(f),MSG_NOSIGNAL)==sizeof(f)?0:-1;
}
/* Internal native callback only: no exec/path/PID/command wire interface. */
static void reap_bounded(void) {
 int64_t until=now_ms()+250;
 do { while(waitpid(-1,NULL,WNOHANG)>0) {} poll(NULL,0,5); } while(now_ms()<until);
}
static void watchdog(int fd, int ownerfd, void (*child)(int), int arg, int64_t deadline) {
 int boot[2];if(socketpair(AF_UNIX,SOCK_SEQPACKET|SOCK_CLOEXEC,0,boot)) _exit(125);
 pid_t parent=getpid();
 pid_t p=fork();
 if(p<0) _exit(125);
 if(!p) {
  if(setpgid(0,0) || prctl(PR_SET_PDEATHSIG,SIGKILL) || getppid()!=parent) _exit(126);
  if(clean_fds(arg,boot[1],-1)) _exit(126);
  int ok=1;if(send(boot[1],&ok,sizeof(ok),MSG_NOSIGNAL)!=sizeof(ok)) _exit(126);
  close(boot[1]);
  child(arg); _exit(0);
 }
 (void)setpgid(p,p);
 close(boot[1]);struct pollfd bf={boot[0],POLLIN,0};int ok=0;
 if(poll(&bf,1,HP_WATCHDOG_MS)!=1 || recv(boot[0],&ok,sizeof(ok),MSG_TRUNC)!=sizeof(ok) || ok!=1) {
  kill(-p,SIGKILL);kill(p,SIGKILL);close(boot[0]);_exit(125);
 }
 close(boot[0]);close(arg);
 if(send(fd,&p,sizeof(p),MSG_NOSIGNAL)!=sizeof(p)) {kill(-p,SIGKILL);kill(p,SIGKILL);_exit(125);}
 int64_t alive=now_ms()+HP_WATCHDOG_MS;
 for(;;) {
  if(now_ms()>=deadline || now_ms()>=alive) break;
  struct pollfd pollfd={fd,POLLIN,0};
  if(poll(&pollfd,1,20)<0 && errno!=EINTR) break;
  if(pollfd.revents) {
   int64_t next;
   ssize_t n=recv(fd,&next,sizeof(next),MSG_DONTWAIT|MSG_TRUNC);
   if(n!=sizeof(next) || next<deadline) break;
   deadline=next; alive=now_ms()+HP_WATCHDOG_MS;
  }
  if(send(fd,&p,sizeof(p),MSG_DONTWAIT|MSG_NOSIGNAL)!=sizeof(p)) break;
  /* WNOWAIT keeps the leader PID reserved until group cleanup. */
  siginfo_t info; memset(&info,0,sizeof(info));
  if(waitid(P_PID,p,&info,WEXITED|WNOHANG|WNOWAIT) || info.si_pid) break;
 }
 /* This group is created here, with its unreaped leader still owned here.
  * No caller-supplied PID, path, process group or socket is accepted. */
 kill(-p,SIGKILL); kill(p,SIGKILL);
 syscall(SYS_pidfd_send_signal,ownerfd,SIGKILL,NULL,0);
 reap_bounded(); close(fd); close(ownerfd); _exit(0);
}
int hp_guard_start(struct hp_guard *g, uint64_t gen, uint64_t epoch, unsigned temporary_ms, void (*child)(int), int arg) {
 if(!gen || !epoch || temporary_ms>86400000 || !child) {errno=EINVAL;return -1;}
 memset(g,0,sizeof(*g)); g->generation=gen;g->epoch=epoch;
 if(getrandom(g->token,16,0)!=16) return -1;
 int probe=syscall(SYS_pidfd_open,getpid(),0);if(probe<0) return -1;close(probe);
 int pair[2]; if(socketpair(AF_UNIX,SOCK_SEQPACKET|SOCK_CLOEXEC,0,pair)) return -1;
 int64_t started=now_ms(), deadline=started+HP_WINDOW_MS;
 int64_t limit=temporary_ms?started+temporary_ms:INT64_MAX;
 if(deadline>limit) deadline=limit;
 pid_t pid=fork();
 if(pid<0) {close(pair[0]);close(pair[1]);return -1;}
 if(pid) {
  close(pair[1]);int ok=0;struct pollfd r={pair[0],POLLIN,0};
  if(poll(&r,1,HP_WINDOW_MS)!=1 || recv(pair[0],&ok,sizeof(ok),MSG_DONTWAIT|MSG_TRUNC)!=sizeof(ok) || ok!=1) {
   close(pair[0]);int64_t until=now_ms()+HP_WINDOW_MS;
   while(waitpid(pid,NULL,WNOHANG)==0 && now_ms()<until) poll(NULL,0,5);
   errno=EIO;return -1;
  }
  g->fd=pair[0];g->pid=pid;return 0;
 }
 close(pair[0]);
 if(setpgid(0,0)) _exit(125);
 if(clean_fds(pair[1],arg,-1)) _exit(125);
 int ownerfd=syscall(SYS_pidfd_open,getpid(),0);
 int inner[2];
 if(ownerfd<0 || socketpair(AF_UNIX,SOCK_SEQPACKET|SOCK_CLOEXEC,0,inner)) _exit(125);
 pid_t w=fork(); if(w<0) _exit(125);
 if(!w) {if(setpgid(0,0) || clean_fds(inner[1],ownerfd,arg)) _exit(125);watchdog(inner[1],ownerfd,child,arg,deadline);}
 close(inner[1]);close(ownerfd);
 close(arg);
 int wfd=syscall(SYS_pidfd_open,w,0);pid_t data=0;
 struct pollfd ready={inner[0],POLLIN,0};
 if(wfd<0 || poll(&ready,1,HP_WATCHDOG_MS)!=1 || recv(inner[0],&data,sizeof(data),MSG_TRUNC)!=sizeof(data) || data<=0) {
  if(wfd>=0) syscall(SYS_pidfd_send_signal,wfd,SIGKILL,NULL,0);
  close(pair[1]);close(inner[0]);reap_bounded();_exit(125);
 }
 int64_t peer_until=now_ms()+HP_WATCHDOG_MS;
 int ok=1;if(now_ms()>=deadline || send(pair[1],&ok,sizeof(ok),MSG_DONTWAIT|MSG_NOSIGNAL)!=sizeof(ok)) peer_until=0;
 for(;;) {
  if(now_ms()>=deadline || now_ms()>=peer_until) break;
  struct pollfd peers[2]={{inner[0],POLLIN,0},{wfd,POLLIN,0}};
  if(poll(peers,2,0)<0 || peers[1].revents) break;
  if(peers[0].revents) {
   pid_t beat=0;
   if(recv(inner[0],&beat,sizeof(beat),MSG_DONTWAIT|MSG_TRUNC)!=sizeof(beat) || beat!=data) break;
   peer_until=now_ms()+HP_WATCHDOG_MS;
  }
  struct pollfd f={pair[1],POLLIN,0};
  if(poll(&f,1,25)<0 && errno!=EINTR) break;
  if(f.revents) {
   int valid=0, stop=0;
   for(int i=0;i<32;i++) {
    struct hp_frame frame;
    ssize_t n=recv(pair[1],&frame,sizeof(frame),MSG_DONTWAIT|MSG_TRUNC);
    if(n<0 && (errno==EAGAIN || errno==EWOULDBLOCK)) break;
    if(n!=sizeof(frame) || frame.generation!=gen || frame.epoch!=epoch ||
       frame.sequence!=g->sequence+1 || memcmp(frame.token,g->token,16) ||
       frame.reserved || (frame.operation!=1 && frame.operation!=2)) {stop=1;break;}
    g->sequence=frame.sequence;
    if(frame.operation==2) {stop=1;break;}
    valid=1;
    if(i==31) stop=1; /* bounded drain: flooding cannot extend authority */
   }
   if(stop || now_ms()>=deadline) break;
   if(valid) {deadline=now_ms()+HP_WINDOW_MS;if(deadline>limit) deadline=limit;}
  }
  if(send(inner[0],&deadline,sizeof(deadline),MSG_DONTWAIT|MSG_NOSIGNAL)!=sizeof(deadline)) break;
 }
 /* The watchdog reserves the leader until it has killed this guardian.
  * While watchdog is alive this is an owned, unreaped group, never caller PID. */
 struct pollfd exited={wfd,POLLIN,0};
 if(poll(&exited,1,0)==0) kill(-data,SIGKILL);
 syscall(SYS_pidfd_send_signal,wfd,SIGKILL,NULL,0);
 close(wfd);close(pair[1]);close(inner[0]);reap_bounded();_exit(0);
}
#ifndef HP_GUARD_TEST
/* No provider has been integrated: packaged executable cannot start anything. */
int main(void) { fputs("HomePublish guardian provider unavailable; activation disabled\n",stderr); return 78; }
#endif
