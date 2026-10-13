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
#ifdef HP_GUARD_TEST
static int64_t now_ms(void) {
 struct timespec t;
 if(clock_gettime(CLOCK_MONOTONIC,&t)) _exit(125);
 return (int64_t)t.tv_sec*1000+t.tv_nsec/1000000;
}
#endif
int hp_guard_send(struct hp_guard *g, uint32_t op) {
 struct hp_frame f={.generation=g->generation,.epoch=g->epoch,.sequence=++g->sequence,.operation=op};
 memcpy(f.token,g->token,16);
 return send(g->fd,&f,sizeof(f),MSG_NOSIGNAL)==sizeof(f)?0:-1;
}
#ifdef HP_GUARD_TEST
/* The host-only callback is compiled out of the packaged helper. */
static void reap_bounded(void) {
 int64_t until=now_ms()+250;
 do { while(waitpid(-1,NULL,WNOHANG)>0) {} poll(NULL,0,5); } while(now_ms()<until);
}
static void watchdog(int fd, int ownerfd, void (*child)(int), int arg, int64_t deadline) {
 pid_t parent=getpid();
 pid_t p=fork();
 if(p<0) _exit(125);
 if(!p) {
  if(setpgid(0,0) || prctl(PR_SET_PDEATHSIG,SIGKILL) || getppid()!=parent) _exit(126);
  close(fd); close(ownerfd); child(arg); _exit(0);
 }
 (void)setpgid(p,p);
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
 int pair[2]; if(socketpair(AF_UNIX,SOCK_SEQPACKET|SOCK_CLOEXEC,0,pair)) return -1;
 int64_t started=now_ms(), deadline=started+HP_WINDOW_MS;
 int64_t limit=temporary_ms?started+temporary_ms:INT64_MAX;
 if(deadline>limit) deadline=limit;
 pid_t pid=fork();
 if(pid<0) {close(pair[0]);close(pair[1]);return -1;}
 if(pid) {close(pair[1]);g->fd=pair[0];g->pid=pid;return 0;}
 close(pair[0]);
 int ownerfd=syscall(SYS_pidfd_open,getpid(),0);
 int inner[2];
 if(ownerfd<0 || socketpair(AF_UNIX,SOCK_SEQPACKET|SOCK_CLOEXEC,0,inner)) _exit(125);
 pid_t w=fork(); if(w<0) _exit(125);
 if(!w) {close(pair[1]);close(inner[0]);watchdog(inner[1],ownerfd,child,arg,deadline);}
 close(inner[1]);close(ownerfd);
 for(;;) {
  if(now_ms()>=deadline) break;
  struct pollfd f={pair[1],POLLIN,0};
  if(poll(&f,1,25)<0 && errno!=EINTR) break;
  if(f.revents) break; /* Initial slice: no renew yet. */
  if(send(inner[0],&deadline,sizeof(deadline),MSG_DONTWAIT|MSG_NOSIGNAL)!=sizeof(deadline)) break;
 }
 close(pair[1]);close(inner[0]);reap_bounded();_exit(0);
}
#else
/* No provider has been integrated: packaged executable cannot start anything. */
int main(void) { fputs("HomePublish guardian provider unavailable; activation disabled\n",stderr); return 78; }
#endif
