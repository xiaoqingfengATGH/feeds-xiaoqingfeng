#define _GNU_SOURCE
#include "renewable-guard.h"
#include <errno.h>
#include <poll.h>
#include <signal.h>
#include <string.h>
#include <sys/prctl.h>
#include <sys/random.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <stddef.h>
#include <sys/mman.h>
#include <stdatomic.h>
struct startup_state { _Atomic pid_t data; };
#include <linux/audit.h>
#include <linux/filter.h>
#include <linux/seccomp.h>
#include <linux/sched.h>
#include <linux/capability.h>
#include "owned-runtime.inc"
/* The provider is trusted fixed native code, never a caller-selected command.
 * Fork/exec inherit this boundary. No credential transitions: supervisors must
 * retain signal permission. Non-root only; privileged Nginx/user directives are
 * not supported by this slice. This is not a filesystem or cgroup sandbox. */
static int worker_boundary(int private_pair) {
#if defined(__x86_64__)
 const unsigned arch=AUDIT_ARCH_X86_64;
#elif defined(__aarch64__)
 const unsigned arch=AUDIT_ARCH_AARCH64;
#else
 errno=ENOTSUP;return -1;
#endif
#if defined(__x86_64__) || defined(__aarch64__)
 if(geteuid()==0 || getuid()!=geteuid() || getgid()!=getegid()) {errno=EPERM;return -1;}
 struct __user_cap_header_struct h={.version=_LINUX_CAPABILITY_VERSION_3,.pid=0};
 struct __user_cap_data_struct caps[2]={{0},{0}};
 if(syscall(SYS_capset,&h,caps)) return -1;
#define DENY(n) BPF_JUMP(BPF_JMP|BPF_JEQ|BPF_K,(n),0,1), BPF_STMT(BPF_RET|BPF_K,SECCOMP_RET_ERRNO|EPERM)
 struct sock_filter code[]={
  BPF_STMT(BPF_LD|BPF_W|BPF_ABS,offsetof(struct seccomp_data,arch)),
  BPF_JUMP(BPF_JMP|BPF_JEQ|BPF_K,arch,1,0),
  BPF_STMT(BPF_RET|BPF_K,SECCOMP_RET_KILL_PROCESS),
  BPF_STMT(BPF_LD|BPF_W|BPF_ABS,offsetof(struct seccomp_data,nr)),
#if defined(__x86_64__)
  /* Reject x32, including unknown/invalid syscall numbers with the ABI bit. */
  BPF_JUMP(BPF_JMP|BPF_JSET|BPF_K,0x40000000U,0,1),
  BPF_STMT(BPF_RET|BPF_K,SECCOMP_RET_KILL_PROCESS),
#endif
  DENY(SYS_setsid), DENY(SYS_setpgid), DENY(SYS_unshare), DENY(SYS_setns),
  /* clone3 has indirect flags: ENOSYS lets libc fall back to checked clone. */
#ifdef SYS_clone3
  BPF_JUMP(BPF_JMP|BPF_JEQ|BPF_K,SYS_clone3,0,1),
  BPF_STMT(BPF_RET|BPF_K,SECCOMP_RET_ERRNO|ENOSYS),
#endif
  BPF_JUMP(BPF_JMP|BPF_JEQ|BPF_K,SYS_clone,0,4),
  BPF_STMT(BPF_LD|BPF_W|BPF_ABS,offsetof(struct seccomp_data,args[0])),
  BPF_JUMP(BPF_JMP|BPF_JSET|BPF_K,CLONE_NEWNS|CLONE_NEWCGROUP|CLONE_NEWUTS|CLONE_NEWIPC|CLONE_NEWUSER|CLONE_NEWPID|CLONE_NEWNET|CLONE_PARENT|CLONE_UNTRACED,0,1),
  BPF_STMT(BPF_RET|BPF_K,SECCOMP_RET_ERRNO|EPERM),
  BPF_STMT(BPF_LD|BPF_W|BPF_ABS,offsetof(struct seccomp_data,nr)),
  DENY(SYS_ptrace), DENY(SYS_process_vm_readv), DENY(SYS_process_vm_writev),
  DENY(SYS_pidfd_getfd),
  DENY(private_pair ? (unsigned)-1 : SYS_recvmsg),
  DENY(private_pair ? (unsigned)-1 : SYS_recvmmsg),
  /* Only the internal fixed-provider test path selects this profile. Every
   * surviving external argument is a pipe, and boot IPC closes before provider
   * entry. UNIX sockets can then arise only from connected STREAM pairs. Never
   * permit DGRAM pairs: they can bind/reconnect to foreign UNIX senders. */
  BPF_JUMP(BPF_JMP|BPF_JEQ|BPF_K,private_pair ? SYS_socket : (unsigned)-1,0,5),
  BPF_STMT(BPF_LD|BPF_W|BPF_ABS,offsetof(struct seccomp_data,args[0])),
  BPF_JUMP(BPF_JMP|BPF_JEQ|BPF_K,AF_INET,2,0),
  BPF_JUMP(BPF_JMP|BPF_JEQ|BPF_K,AF_INET6,1,0),
  BPF_STMT(BPF_RET|BPF_K,SECCOMP_RET_ERRNO|EPERM),
  BPF_STMT(BPF_LD|BPF_W|BPF_ABS,offsetof(struct seccomp_data,nr)),
  BPF_JUMP(BPF_JMP|BPF_JEQ|BPF_K,private_pair ? SYS_socketpair : (unsigned)-1,0,11),
  BPF_STMT(BPF_LD|BPF_W|BPF_ABS,offsetof(struct seccomp_data,args[0])),
  BPF_JUMP(BPF_JMP|BPF_JEQ|BPF_K,AF_UNIX,1,0),
  BPF_STMT(BPF_RET|BPF_K,SECCOMP_RET_ERRNO|EPERM),
  BPF_STMT(BPF_LD|BPF_W|BPF_ABS,offsetof(struct seccomp_data,args[1])),
  BPF_STMT(BPF_ALU|BPF_AND|BPF_K,~(SOCK_CLOEXEC|SOCK_NONBLOCK)),
  BPF_JUMP(BPF_JMP|BPF_JEQ|BPF_K,SOCK_STREAM,1,0),
  BPF_STMT(BPF_RET|BPF_K,SECCOMP_RET_ERRNO|EPERM),
  BPF_STMT(BPF_LD|BPF_W|BPF_ABS,offsetof(struct seccomp_data,args[2])),
  BPF_JUMP(BPF_JMP|BPF_JEQ|BPF_K,0,1,0),
  BPF_STMT(BPF_RET|BPF_K,SECCOMP_RET_ERRNO|EPERM),
  BPF_STMT(BPF_LD|BPF_W|BPF_ABS,offsetof(struct seccomp_data,nr)),
  DENY(SYS_io_uring_setup), DENY(SYS_bpf), DENY(SYS_mount), DENY(SYS_umount2),
  DENY(SYS_pivot_root), DENY(SYS_chroot), DENY(SYS_capset),
  DENY(SYS_setuid), DENY(SYS_setgid), DENY(SYS_setreuid), DENY(SYS_setregid),
  DENY(SYS_setresuid), DENY(SYS_setresgid), DENY(SYS_setfsuid), DENY(SYS_setfsgid), DENY(SYS_setgroups),
#ifdef SYS_open_by_handle_at
  DENY(SYS_open_by_handle_at),
#endif
#ifdef SYS_fsopen
  DENY(SYS_fsopen), DENY(SYS_fsmount), DENY(SYS_fspick), DENY(SYS_move_mount), DENY(SYS_open_tree),
#endif
  BPF_STMT(BPF_RET|BPF_K,SECCOMP_RET_ALLOW)
 };
#undef DENY
 struct sock_fprog prog={.len=sizeof(code)/sizeof(code[0]),.filter=code};
 if(prctl(PR_SET_NO_NEW_PRIVS,1,0,0,0)) return -1;
 return prctl(PR_SET_SECCOMP,SECCOMP_MODE_FILTER,&prog);
#endif
}
/* Fail closed without close_range: never rely on CLOEXEC for fork callbacks. */
static int clean_fds(int a,int b,int c) {
 int keep[14]={a,b,c,owned_runtime?owned_runtime->dir:-1,owned_runtime?owned_runtime->parent:-1};
 for(int i=0;i<4;i++)keep[5+i]=owned_runtime?owned_runtime->entries[i].fd:-1;
 for(int i=0;i<5;i++)keep[9+i]=owned_runtime?owned_runtime->dirs[i].fd:-1;
 for(int i=0;i<14;i++) for(int j=i+1;j<14;j++) if(keep[j]<keep[i]) {int t=keep[i];keep[i]=keep[j];keep[j]=t;}
 unsigned first=0;
 for(int i=0;i<14;i++) {
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
static int provider_exited(pid_t pid) {
 /* The unreaped owned leader is reserved by watchdog or subreaper adoption.
  * Observe actual kernel exit, not an arbitrary grace sleep, before unlink. */
 int fd=syscall(SYS_pidfd_open,pid,0);if(fd<0)return 0;
 int64_t until=now_ms()+250;int ready=0;
 do {
  int64_t remaining=until-now_ms();if(remaining<=0)break;
  struct pollfd p={fd,POLLIN,0};
  int rc=poll(&p,1,(int)remaining);
  if(rc>0 && (p.revents&POLLIN)){ready=1;break;}
  if(rc<0 && errno!=EINTR)break;
 } while(now_ms()<until);
 close(fd);return ready;
}
static void watchdog(int fd, int ownerfd, void (*child)(int), int arg, int64_t deadline, struct startup_state *state, int private_pair) {
 int boot[2];if(socketpair(AF_UNIX,SOCK_SEQPACKET|SOCK_CLOEXEC,0,boot)) _exit(125);
 pid_t parent=getpid();
 pid_t p=fork();
 if(p<0) _exit(125);
 if(!p) {
  if(prctl(PR_SET_PDEATHSIG,SIGKILL) || getppid()!=parent) _exit(126);
  int go=0;struct pollfd gate={boot[1],POLLIN,0};
  if(poll(&gate,1,HP_WATCHDOG_MS)!=1 || recv(boot[1],&go,sizeof(go),MSG_TRUNC)!=sizeof(go) || go!=1 || setpgid(0,0)) _exit(126);
  struct stat argument;
  if(private_pair && (fstat(arg,&argument) || !S_ISFIFO(argument.st_mode))) _exit(126);
  if(clean_fds(arg,boot[1],-1) || worker_boundary(private_pair)) _exit(126);
  int ok=1;if(send(boot[1],&ok,sizeof(ok),MSG_NOSIGNAL)!=sizeof(ok)) _exit(126);
  close(boot[1]);
  munmap(state,sizeof(*state));
  child(arg); _exit(0);
 }
 atomic_store_explicit(&state->data,p,memory_order_release);
 int go=1;
 if(send(boot[0],&go,sizeof(go),MSG_NOSIGNAL)!=sizeof(go)) {kill(p,SIGKILL);_exit(125);}
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
 /* Never kill the reciprocal cleaner before completing our own cleanup.
  * Both guards may reach this tail together; killing first can kill BOTH
  * cleaners with every owned secret still linked. Pinned identities plus
  * ENOENT-tolerant unlink make concurrent cleanup idempotent, not a lock. */
 int residual=provider_exited(p)?hp_owned_cleanup(owned_runtime):1;
 syscall(SYS_pidfd_send_signal,ownerfd,SIGKILL,NULL,0);
 reap_bounded();close(fd); close(ownerfd); _exit(residual?124:0);
}
static int guard_start(struct hp_guard *g, uint64_t gen, uint64_t epoch, unsigned temporary_ms, void (*child)(int), int arg, int private_pair) {
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
   close(pair[0]);
   /* Direct unreaped child identity, not caller PID or kernel fallback. A
    * pre-fork SIGSTOP cannot be recovered by closing IPC alone. */
   kill(pid,SIGKILL);
   int64_t until=now_ms()+HP_WINDOW_MS;
   while(waitpid(pid,NULL,WNOHANG)==0 && now_ms()<until) poll(NULL,0,5);
   errno=EIO;return -1;
  }
  g->fd=pair[0];g->pid=pid;return 0;
 }
 close(pair[0]);
 if(prctl(PR_SET_CHILD_SUBREAPER,1) || setpgid(0,0)) _exit(125);
 if(clean_fds(pair[1],arg,-1)) _exit(125);
 int ownerfd=syscall(SYS_pidfd_open,getpid(),0);
 int inner[2];
 if(ownerfd<0 || socketpair(AF_UNIX,SOCK_SEQPACKET|SOCK_CLOEXEC,0,inner)) _exit(125);
 struct startup_state *state=mmap(NULL,sizeof(*state),PROT_READ|PROT_WRITE,MAP_SHARED|MAP_ANONYMOUS,-1,0);
 if(state==MAP_FAILED) _exit(125);
 atomic_init(&state->data,0);
 pid_t w=fork(); if(w<0) _exit(125);
 if(!w) {if(setpgid(0,0) || clean_fds(inner[1],ownerfd,arg)) _exit(125);watchdog(inner[1],ownerfd,child,arg,deadline,state,private_pair);}
 close(inner[1]);close(ownerfd);
 close(arg);
 int wfd=syscall(SYS_pidfd_open,w,0);pid_t data=0;
 struct pollfd ready={inner[0],POLLIN,0};
 if(wfd<0 || poll(&ready,1,HP_WATCHDOG_MS)!=1 || recv(inner[0],&data,sizeof(data),MSG_TRUNC)!=sizeof(data) || data<=0) {
  pid_t pending=atomic_load_explicit(&state->data,memory_order_acquire);
  /* Both identities still unreaped here; include pre-isolation children in
   * the watchdog group and the separately registered provider group. */
  if(pending>0) {kill(-pending,SIGKILL);kill(pending,SIGKILL);}
  kill(-w,SIGKILL);kill(w,SIGKILL);
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
 /* If watchdog died, subreaper adoption reserves the data leader here.
  * If alive, it holds WNOWAIT until killing us. Never reap before group kill. */
 kill(-data,SIGKILL);
 close(pair[1]);close(inner[0]);
 /* As above, cleanup must precede killing the other possible cleaner. */
 int residual=provider_exited(data)?hp_owned_cleanup(owned_runtime):1;
 syscall(SYS_pidfd_send_signal,wfd,SIGKILL,NULL,0);close(wfd);
 reap_bounded();_exit(residual?124:0);
}
int hp_guard_start(struct hp_guard *g, uint64_t gen, uint64_t epoch, unsigned temporary_ms, void (*child)(int), int arg) {
 return guard_start(g,gen,epoch,temporary_ms,child,arg,0);
}
#ifdef HP_GUARD_TEST
/* Deliberately absent from public header and production builds. Fixed cached
 * Nginx fixture only; no production exec/inode authority is claimed. */
int hp_guard_start_private_test(struct hp_guard *g, uint64_t gen, uint64_t epoch, unsigned temporary_ms, void (*child)(int), int arg) {
 return guard_start(g,gen,epoch,temporary_ms,child,arg,1);
}
#endif
#ifndef HP_GUARD_TEST
/* No provider has been integrated: packaged executable cannot start anything. */
int main(void) { fputs("HomePublish guardian provider unavailable; activation disabled\n",stderr); return 78; }
#endif
