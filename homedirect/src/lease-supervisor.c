/* SPDX-License-Identifier: Apache-2.0
 * Linux lease helper; compile for target libc/architecture, never setuid.
 * Source trust excludes malicious root. All reads are descriptor-relative.
 */
#define _GNU_SOURCE
#include <sys/stat.h>
#include <sys/wait.h>
#include <sys/file.h>
#include <fcntl.h>
#include <unistd.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <time.h>
#include <poll.h>
#include <sys/prctl.h>
#include <sys/mman.h>
#include <sys/random.h>
#include <stddef.h>
#include <sys/syscall.h>
#include <linux/audit.h>
#include <linux/filter.h>
#include <linux/seccomp.h>

/* Use target headers, never guessed syscall numbers. Unsupported target ABIs
 * fail at build time rather than silently running an unconfined root engine. */
#if defined(__x86_64__)
#define HOMEDIRECT_AUDIT_ARCH AUDIT_ARCH_X86_64
#elif defined(__i386__)
#define HOMEDIRECT_AUDIT_ARCH AUDIT_ARCH_I386
#elif defined(__aarch64__)
#define HOMEDIRECT_AUDIT_ARCH AUDIT_ARCH_AARCH64
#elif defined(__arm__)
#define HOMEDIRECT_AUDIT_ARCH AUDIT_ARCH_ARM
#elif defined(__riscv) && __riscv_xlen == 64
#define HOMEDIRECT_AUDIT_ARCH AUDIT_ARCH_RISCV64
#elif defined(__mips__)
#include <asm/sgidefs.h>
#if _MIPS_SIM == _ABIO32
#ifdef __MIPSEL__
#define HOMEDIRECT_AUDIT_ARCH AUDIT_ARCH_MIPSEL
#else
#define HOMEDIRECT_AUDIT_ARCH AUDIT_ARCH_MIPS
#endif
#elif _MIPS_SIM == _ABI64
#ifdef __MIPSEL__
#define HOMEDIRECT_AUDIT_ARCH AUDIT_ARCH_MIPSEL64
#else
#define HOMEDIRECT_AUDIT_ARCH AUDIT_ARCH_MIPS64
#endif
#elif _MIPS_SIM == _ABIN32
#ifdef __MIPSEL__
#define HOMEDIRECT_AUDIT_ARCH AUDIT_ARCH_MIPSEL64N32
#else
#define HOMEDIRECT_AUDIT_ARCH AUDIT_ARCH_MIPS64N32
#endif
#endif
#endif
#ifndef HOMEDIRECT_AUDIT_ARCH
#error Unsupported HomeDirect seccomp target ABI
#endif
#ifndef __NR_pidfd_getfd
#error Target headers must define pidfd_getfd for the security boundary
#endif

static int confine_natmap(void) {
 /* Inherited across exec/fork; no_new_privs prevents privilege transitions.
  * Deny the descriptor import used by upstream's foreign SO_REUSEPORT fallback.
  * This is a narrow upstream safety boundary, not a sandbox for malicious root. */
 struct sock_filter code[]={
  BPF_STMT(BPF_LD|BPF_W|BPF_ABS,offsetof(struct seccomp_data,arch)),
  BPF_JUMP(BPF_JMP|BPF_JEQ|BPF_K,HOMEDIRECT_AUDIT_ARCH,1,0),
  BPF_STMT(BPF_RET|BPF_K,SECCOMP_RET_KILL_PROCESS),
  BPF_STMT(BPF_LD|BPF_W|BPF_ABS,offsetof(struct seccomp_data,nr)),
#if defined(__x86_64__)
  /* x32 shares the audit arch but uses a different syscall-number namespace. */
  BPF_JUMP(BPF_JMP|BPF_JSET|BPF_K,0x40000000U,0,1),
  BPF_STMT(BPF_RET|BPF_K,SECCOMP_RET_KILL_PROCESS),
#endif
  BPF_JUMP(BPF_JMP|BPF_JEQ|BPF_K,__NR_pidfd_getfd,0,1),
  BPF_STMT(BPF_RET|BPF_K,SECCOMP_RET_ERRNO|EPERM),
  BPF_STMT(BPF_RET|BPF_K,SECCOMP_RET_ALLOW),
 };
 struct sock_fprog program={.len=sizeof code/sizeof *code,.filter=code};
 if(prctl(PR_SET_NO_NEW_PRIVS,1,0,0,0)) return -1;
 return prctl(PR_SET_SECCOMP,SECCOMP_MODE_FILTER,&program);
}

static volatile pid_t *active_group;
static void cleanup_snapshot(int d,int root) {
 const char *files[]={"nginx.conf","cert.pem","key.pem","nginx.pid","error.log"};
 const char *dirs[]={"body","proxy","scgi_temp","uwsgi_temp","fastcgi_temp"};
 for(size_t i=0;i<sizeof files/sizeof *files;i++) unlinkat(d,files[i],0);
 for(size_t i=0;i<sizeof dirs/sizeof *dirs;i++) unlinkat(d,dirs[i],AT_REMOVEDIR);
 unlinkat(root,"runner.lock",AT_REMOVEDIR);
}

static void execute(const char *r,int test);
static int cleanup_root=-1;
static int provisioning;
static const char *provision_path;
struct owned_entry { struct stat identity; volatile sig_atomic_t ready; };
struct provision_owner { struct owned_entry dir,files[5]; };
static struct provision_owner *provision_owner;
static const char *provision_files[]={"nginx.conf","cert.pem","key.pem","router.token","session"};
static int publication;
static double publication_deadline;
struct preparation { int root; const char *r,*snap,*cfg,*cert,*key; };
static void provision(const struct preparation *p);
static void prepare(const struct preparation *p);
static volatile sig_atomic_t cancelled;
static void cancel(int sig) { (void)sig; cancelled=1; }
static double monotonic(void) {
 struct timespec ts; if(clock_gettime(CLOCK_MONOTONIC,&ts)) { perror("clock"); exit(2); }
 return (double)ts.tv_sec+(double)ts.tv_nsec/1000000000.0;
}
/* Guardian owns a separate process group per phase. Killing the master alone
 * is insufficient: stopped workers and established connections must die too. */
static int phase(const char *snap,int test,int control,double deadline,const struct preparation *prep) {
 pid_t owner=getpid();
 pid_t p=fork(); if(p<0) return 2;
 if(!p) {
  if(prctl(PR_SET_PDEATHSIG,SIGKILL) || getppid()!=owner) _exit(126);
  cleanup_root=-1; /* Only the guardian removes the shared snapshot. */
  close(control); if(setpgid(0,0)) _exit(126);
  if(prep) {if(provisioning) provision(prep);else prepare(prep);_exit(0);}
  execute(snap,test);
 }
 if(setpgid(p,p) && errno!=EACCES && errno!=ESRCH) {
  kill(p,SIGKILL); /* Still run the bounded collection path below. */
 }
 *active_group=p;
 int status=0,rc=2;
 for(;;) {
  pid_t w=waitpid(p,&status,WNOHANG);
  if(w==p) {rc=WIFEXITED(status)?WEXITSTATUS(status):2;break;}
  if(w<0 && errno!=EINTR) break;
  if(monotonic()>=deadline) {rc=test?2:0;break;}
  struct pollfd fd={.fd=control,.events=POLLIN|POLLHUP};
  if(poll(&fd,1,20)>0) break; /* controller died or requested shutdown */
 }
 kill(-p,SIGKILL); /* hard close, including workers, no graceful-drain overrun */
 /* Never block on a killed task: uninterruptible kernel I/O is not bounded.
  * Collect asynchronously adopted workers as well as the direct phase child. */
 double reap_until=monotonic()+0.25;
 do {
  while(waitpid(-1,&status,WNOHANG)>0) {}
  poll(NULL,0,10);
 } while(monotonic()<reap_until);
 *active_group=0;
 return rc;
}

static int same_entry(int parent,const char *name,const struct owned_entry *entry) {
 struct stat st;
 return entry->ready && !fstatat(parent,name,&st,AT_SYMLINK_NOFOLLOW) &&
  st.st_dev==entry->identity.st_dev && st.st_ino==entry->identity.st_ino;
}
static void cleanup_provision(int tmp) {
 const char *name=provision_path+5;
 if(!provision_owner->dir.ready) {
  /* Name was absent under the /tmp inode exclusion before the phase. A
   * mkdir-to-identity crash can leave only an empty directory, never TLS. */
  unlinkat(tmp,name,AT_REMOVEDIR);
  return;
 }
 if(!same_entry(tmp,name,&provision_owner->dir)) return;
 int d=openat(tmp,name,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC);
 if(d<0) return;
 struct stat st;
 if(fstat(d,&st) || st.st_dev!=provision_owner->dir.identity.st_dev ||
    st.st_ino!=provision_owner->dir.identity.st_ino) {close(d);return;}
 for(size_t i=0;i<5;i++) if(same_entry(d,provision_files[i],&provision_owner->files[i])) unlinkat(d,provision_files[i],0);
 /* Runtime artifacts are created only by the trusted dedicated nginx. */
 const char *files[]={"nginx.pid","error.log"};
 const char *dirs[]={"body","proxy","scgi_temp","uwsgi_temp","fastcgi_temp"};
 for(size_t i=0;i<sizeof files/sizeof *files;i++) unlinkat(d,files[i],0);
 for(size_t i=0;i<sizeof dirs/sizeof *dirs;i++) unlinkat(d,dirs[i],AT_REMOVEDIR);
 close(d);
 if(same_entry(tmp,name,&provision_owner->dir)) unlinkat(tmp,name,AT_REMOVEDIR);
}
static void cleanup_owned(int root) {
 if(provisioning) {cleanup_provision(root);return;}
 int d=openat(root,"runner.lock",O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC);
 if(d>=0) {cleanup_snapshot(d,root);close(d);}
}
static void on_exit_cleanup(void) {
 if(cleanup_root>=0) cleanup_owned(cleanup_root);
}
static void die(const char *s) { perror(s); exit(2); }
static int safe(int fd, int dir) {
 struct stat s;
 return fstat(fd,&s)==0 && s.st_uid==0 && (dir?S_ISDIR(s.st_mode):S_ISREG(s.st_mode)) &&
  !(s.st_mode & 0077) && (dir || s.st_nlink==1);
}
static int private_dir(int parent,const char *name) {
 int fd=openat(parent,name,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC);
 if(fd<0 || !safe(fd,1)) die("unsafe private directory");
 return fd;
}
static char *read_source(int dir,const char *name) {
 int fd=openat(dir,name,O_RDONLY|O_NOFOLLOW|O_CLOEXEC|O_NONBLOCK);
 if(fd<0 || !safe(fd,0)) die("unsafe source file");
 struct stat st; if(fstat(fd,&st) || st.st_size<1 || st.st_size>65536) die("source size");
 char *p=calloc(1,(size_t)st.st_size+1); if(!p) die("calloc");
 size_t n=0; while(n<(size_t)st.st_size) { ssize_t k=read(fd,p+n,(size_t)st.st_size-n); if(k<=0) die("source read"); n+=(size_t)k; }
 if(memchr(p,0,n)) die("embedded NUL");
 close(fd); return p;
}
static void read_publication_token(int dir,char token[130]) {
 int fd=openat(dir,"router.token",O_RDONLY|O_NOFOLLOW|O_CLOEXEC|O_NONBLOCK);
 if(fd<0 || !safe(fd,0)) die("unsafe publication token");
 /* Independent of stat size: short reads are not EOF, and no invalid bytes
  * may reach snapshot(). Stop at EOF or the 129th-byte oversize sentinel. */
 size_t used=0;
 while(used<129) {
  ssize_t n=read(fd,token+used,129-used);
  if(n<0) {if(errno==EINTR)continue;die("publication token read");}
  if(!n)break;
  used+=(size_t)n;
 }
 close(fd);
 if(used<32 || used>128) {errno=EINVAL;die("publication token size");}
 for(size_t i=0;i<used;i++) {
  unsigned char c=(unsigned char)token[i];
  if(!((c>='a'&&c<='z')||(c>='A'&&c<='Z')||(c>='0'&&c<='9')||c=='_'||c=='-'||c=='.')) {
   errno=EINVAL;die("publication token bytes");
  }
 }
 token[used]=0;
}
static void snapshot(int d,const char *name,const char *text) {
 int fd=openat(d,name,O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW|O_CLOEXEC,0400);
 if(fd<0) die("snapshot create");
 if(provisioning) {
  for(size_t i=0;i<5;i++) if(!strcmp(name,provision_files[i])) {
   if(fstat(fd,&provision_owner->files[i].identity)) die("snapshot identity");
   provision_owner->files[i].ready=1;
  }
 }
 size_t left=strlen(text); while(left) { ssize_t n=write(fd,text,left); if(n<=0) die("snapshot write"); text+=n; left-=(size_t)n; }
 if(fsync(fd)) die("snapshot fsync");
 close(fd);
}
static char *rewrite(const char *s,const char *from,const char *to) {
 size_t count=0,a=strlen(from),b=strlen(to); const char *p=s;
 while((p=strstr(p,from))) {count++;p+=a;}
 char *out=malloc(strlen(s)+count*(b-a)+1),*q=out; if(!out) die("malloc");
 while((p=strstr(s,from))) {size_t n=(size_t)(p-s);memcpy(q,s,n);q+=n;memcpy(q,to,b);q+=b;s=p+a;}
 strcpy(q,s);return out;
}
static const char *map_bind,*map_port,*map_stun,*map_http;
static int endpoint(const char *s) {
 size_t n=strlen(s);if(!n || n>253 || s[0]=='-' || s[0]=='.') return 0;
 for(size_t i=0;i<n;i++) if(!((s[i]>='a'&&s[i]<='z')||(s[i]>='0'&&s[i]<='9')||s[i]=='.'||s[i]=='-'||s[i]==':')) return 0;
 return 1;
}
static int isolated_port(const char *s) {
 if(!*s) return 0;
 for(const char *p=s;*p;p++) if(*p<'0'||*p>'9') return 0;
 char *end;long n=strtol(s,&end,10);return !*end && n>=1024 && n<=65535;
}
static void execute(const char *r,int test) {
 char cfg[512],prefix[512]; snprintf(cfg,sizeof cfg,"%s/nginx.conf",r);snprintf(prefix,sizeof prefix,"%s/",r);
 if(test) execl("/usr/sbin/nginx","nginx","-t","-p",prefix,"-c",cfg,(char*)NULL);
 else if(!map_bind) execl("/usr/sbin/nginx","nginx","-p",prefix,"-c",cfg,"-g","daemon off;",(char*)NULL);
 else {
  /* Both engines remain in the monitored phase group. No daemon/respawn.
   * Either exit closes the other; guardian/controller failure kills the group. */
  if(publication) {
   pid_t b=fork();if(b<0)_exit(127);
   if(!b){execl("/usr/libexec/homedirect-publish","homedirect-publish","--begin",r,(char*)NULL);_exit(127);}
   int status;if(waitpid(b,&status,0)!=b||!WIFEXITED(status)||WEXITSTATUS(status))_exit(126);
  }
  int ready[2];if(pipe2(ready,O_CLOEXEC)) _exit(127);
  pid_t owner=getpid(),m=fork();
  if(m<0) _exit(127);
  if(!m) {
   close(ready[0]);
   if(prctl(PR_SET_PDEATHSIG,SIGKILL) || getppid()!=owner) _exit(126);
   if(confine_natmap()) {perror("NATMap seccomp boundary");_exit(126);}
   if(write(ready[1],"S",1)!=1) _exit(126);
   close(ready[1]);
   if(publication) {
    if(setenv("HOMEDIRECT_RUNTIME",r,1))_exit(126);
    execl("/usr/bin/natmap","natmap","-4","-b",map_bind,"-s",map_stun,"-h",map_http,"-t","127.0.0.1","-p",map_port,"-e","/usr/libexec/homedirect-publish",(char*)NULL);
    _exit(127);
   }
   execl("/usr/bin/natmap","natmap","-4","-b",map_bind,"-s",map_stun,"-h",map_http,"-t","127.0.0.1","-p",map_port,(char*)NULL);
   _exit(127);
  }
  close(ready[1]);
  char ack=0;ssize_t received;
  do {received=read(ready[0],&ack,1);} while(received<0 && errno==EINTR);
  close(ready[0]);
  /* Never launch the TLS listener unless the kernel accepted the boundary.
   * A stalled setup is still bounded by the enclosing guardian/TTL. */
  if(received!=1 || ack!='S') _exit(126);
  pid_t n=fork();if(n<0) _exit(127);
  if(!n) {
   if(prctl(PR_SET_PDEATHSIG,SIGKILL) || getppid()!=owner) _exit(126);
   execl("/usr/sbin/nginx","nginx","-p",prefix,"-c",cfg,"-g","daemon off;",(char*)NULL);
   _exit(127);
  }
  int status;while(waitpid(-1,&status,0)<0) if(errno!=EINTR) _exit(127);
  _exit(2); /* Unexpected engine termination is never a successful lease. */
 }
 _exit(127);
}
static void provision(const struct preparation *p) {
 /* This child is already independently supervised. No secrets exist until
  * the directory and file identities have been published to both monitors. */
 if(mkdirat(p->root,p->r+5,0700)) die("exclusive provision directory");
 int d=private_dir(p->root,p->r+5);
 if(flock(d,LOCK_EX|LOCK_NB) || fstat(d,&provision_owner->dir.identity)) die("provision owner");
 provision_owner->dir.ready=1;
 int etc=open("/etc",O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC);
 if(etc<0) die("certificate parent");
 int source=private_dir(etc,"homedirect");
 char *cert=read_source(source,"cert.pem"),*key=read_source(source,"key.pem");
 snapshot(d,"cert.pem",cert);snapshot(d,"key.pem",key);
 if(publication) {
  char token[130]={0};read_publication_token(source,token);
  snapshot(d,"router.token",token);memset(token,0,sizeof token);
  unsigned char random[16];char nonce[33],state[256];struct timespec wall;
  if(getrandom(random,sizeof random,0)!=(ssize_t)sizeof random||clock_gettime(CLOCK_REALTIME,&wall)) die("publication session");
  for(size_t i=0;i<sizeof random;i++) snprintf(nonce+2*i,3,"%02x",random[i]);
  long long now=(long long)wall.tv_sec*1000+wall.tv_nsec/1000000;
  long long expiry=now+(long long)((publication_deadline-monotonic())*1000);
  snprintf(state,sizeof state,"%lld %s %lld %.9f %s 0\n",now,nonce,expiry,publication_deadline,map_bind);
  snapshot(d,"session",state);
 }
 free(cert);free(key);close(source);close(etc);
 int cfg=openat(d,"nginx.conf",O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW|O_CLOEXEC,0400);
 if(cfg<0 || fstat(cfg,&provision_owner->files[0].identity)) die("render output");
 provision_owner->files[0].ready=1;
 pid_t owner=getpid(),renderer=fork();if(renderer<0) die("render fork");
 if(!renderer) {
  if(prctl(PR_SET_PDEATHSIG,SIGKILL) || getppid()!=owner || dup2(cfg,STDOUT_FILENO)<0) _exit(126);
  execl("/usr/bin/lua","lua","/usr/share/homedirect/config-cli.lua","render","",p->r,(char*)NULL);
  _exit(127);
 }
 int status;while(waitpid(renderer,&status,0)<0) if(errno!=EINTR) die("render wait");
 if(!WIFEXITED(status) || WEXITSTATUS(status) || fsync(cfg)) die("render failed");
 close(cfg);
 char *text=read_source(d,"nginx.conf"),expect[512];
 if(strstr(text,"include") || strstr(text,"load_module")) die("external config forbidden");
 snprintf(expect,sizeof expect,"ssl_certificate %s/cert.pem;",p->r);
 if(!strstr(text,expect)) die("provision certificate required");
 snprintf(expect,sizeof expect,"ssl_certificate_key %s/key.pem;",p->r);
 if(!strstr(text,expect)) die("provision key required");
 free(text);close(d);
}
static void prepare(const struct preparation *p) {
 if(mkdirat(p->root,"runner.lock",0700)) die("exclusive runner lock");
 int d=private_dir(p->root,"runner.lock");
 char *fixed=rewrite(p->cfg,p->r,p->snap);
 snapshot(d,"nginx.conf",fixed);
 snapshot(d,"cert.pem",p->cert);
 snapshot(d,"key.pem",p->key);
 close(d);
 free(fixed);
}
int main(int argc,char **argv) {
 /* Read-only init preflight. Fixed reference only; no secret output, runtime,
  * session, transport or snapshot side effects. Provisioning rechecks via fd. */
 if(argc==3 && !strcmp(argv[1],"--check-publication")) {
  if(geteuid()!=0 || strcmp(argv[2],"/etc/homedirect/router.token")) return 2;
  int etc=open("/etc",O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC);
  if(etc<0) return 2;
  int dir=private_dir(etc,"homedirect");struct stat info;
  if(fstatat(dir,"router.token",&info,AT_SYMLINK_NOFOLLOW) ||
     !S_ISREG(info.st_mode) || info.st_uid!=0 || info.st_nlink!=1 ||
     (info.st_mode&07777)!=0600) return 2;
  char token[130]={0};read_publication_token(dir,token);
  memset(token,0,sizeof token);close(dir);close(etc);return 0;
 }
 /* Minimal target metadata API: no external stat applet/package required.
  * Never follow the final symlink; fail closed and emit nothing on error. */
 if(argc==3 && (!strcmp(argv[1],"--identity") || !strcmp(argv[1],"--metadata"))) {
  struct stat info;
  if(geteuid()!=0 || lstat(argv[2],&info) ||
     (!S_ISREG(info.st_mode) && !S_ISDIR(info.st_mode))) return 2;
  if(!strcmp(argv[1],"--identity"))
   printf("%llu:%llu\n",(unsigned long long)info.st_dev,(unsigned long long)info.st_ino);
  else printf("%llu:%o:%llu\n",(unsigned long long)info.st_uid,
              (unsigned int)(info.st_mode&07777),(unsigned long long)info.st_nlink);
  return 0;
 }
 if((argc!=3 && argc!=7 && argc!=8) || geteuid()!=0) return 2;
 publication=argc==8&&!strcmp(argv[1],"--provision")&&!strcmp(argv[7],"publish");
 if(argc==8&&!publication) return 2;
 if(argc>=7) {
  if(!isolated_port(argv[3]) || !isolated_port(argv[4]) || atoi(argv[3])==atoi(argv[4]) || !endpoint(argv[5]) || !endpoint(argv[6])) return 2;
  map_bind=argv[3];map_port=argv[4];map_stun=argv[5];map_http=argv[6];
 }
 provisioning=argc>=7 && !strcmp(argv[1],"--provision");
 char provision_name[96];
 if(provisioning) {
  unsigned char random[16];
  if(getrandom(random,sizeof random,0)!=(ssize_t)sizeof random) die("provision name");
  strcpy(provision_name,"/tmp/homedirect-service-");
  size_t prefix_length=strlen(provision_name);
  for(size_t i=0;i<sizeof random;i++) snprintf(provision_name+prefix_length+2*i,3,"%02x",random[i]);
 }
 const char *r=provisioning?provision_name:argv[1]; char *end; long ttl=strtol(argv[2],&end,10);
 if(!*argv[2] || *end || ttl<1 || ttl>120 || strncmp(r,"/tmp/homedirect",14) || strlen(r)>200) return 2;
 for(const char *p=r+14;*p;p++) if(!((*p>='a'&&*p<='z')||(*p>='A'&&*p<='Z')||(*p>='0'&&*p<='9')||*p=='-'||*p=='_')) return 2;
 double started=monotonic();publication_deadline=started+(double)ttl;
 umask(077);
 int tmp=open("/tmp",O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC); struct stat st;
 if(tmp<0 || fstat(tmp,&st) || st.st_uid!=0 || ((st.st_mode&0022) && !(st.st_mode&S_ISVTX))) die("unsafe /tmp");
 int root=provisioning?dup(tmp):private_dir(tmp,r+5);
 char *cfg=NULL,*cert=NULL,*key=NULL;
 if(provisioning) {
  provision_path=r;
  provision_owner=mmap(NULL,sizeof *provision_owner,PROT_READ|PROT_WRITE,MAP_SHARED|MAP_ANONYMOUS,-1,0);
  if(provision_owner==MAP_FAILED || root<0) die("provision ownership");
 } else {
 /* Inode-scoped advisory exclusion exists before any directory lock. Shared
  * across fork; a rejected concurrent helper never owns/removes runner.lock. */
 if(flock(root,LOCK_EX|LOCK_NB)) die("exclusive runtime owner");
 cfg=read_source(root,"nginx.conf");cert=read_source(root,"cert.pem");key=read_source(root,"key.pem");
 /* Only standalone generated configurations: no mutable includes/modules. */
 if(strstr(cfg,"include") || strstr(cfg,"load_module")) die("external config forbidden");
 char expect[512];snprintf(expect,sizeof expect,"ssl_certificate %s/cert.pem;",r);
 if(!strstr(cfg,expect)) die("snapshot certificate required");
 snprintf(expect,sizeof expect,"ssl_certificate_key %s/key.pem;",r);
 if(!strstr(cfg,expect)) die("snapshot key required");
 }
 /* No directory or TLS exists before independent supervision in provision mode. */
 char snap[512];snprintf(snap,sizeof snap,provisioning?"%s":"%s/runner.lock",r);
 if(atexit(on_exit_cleanup)) die("cleanup registration");
 int control[2];if(pipe2(control,O_CLOEXEC|O_NONBLOCK)) die("control pipe");
 struct sigaction action={0};action.sa_handler=cancel;sigemptyset(&action.sa_mask);
 if(sigaction(SIGTERM,&action,NULL) || sigaction(SIGINT,&action,NULL)) die("signal handler");
 active_group=mmap(NULL,3*sizeof *active_group,PROT_READ|PROT_WRITE,MAP_SHARED|MAP_ANONYMOUS,-1,0);
 if(active_group==MAP_FAILED) die("shared group");
 if(prctl(PR_SET_CHILD_SUBREAPER,1)) die("controller subreaper");
 pid_t guardian=fork();if(guardian<0) die("guardian fork");
 if(guardian) {
  close(control[0]);
  int status,expired=0;
  double startup_limit=started+2.0;
  if(startup_limit>started+(double)ttl) startup_limit=started+(double)ttl;
  for(;;) {
   if(cancelled && control[1]>=0) {close(control[1]);control[1]=-1;}
   if(monotonic()>=started+(double)ttl) {
    expired=active_group[1]!=0;
    pid_t group=*active_group;if(group>0) kill(-group,SIGKILL);
    kill(guardian,SIGKILL);
   } else if(!active_group[1] && monotonic()>=startup_limit) kill(guardian,SIGKILL);
   pid_t w=waitpid(guardian,&status,WNOHANG);
   if(w==guardian) break;
   if(w<0 && errno!=EINTR) return 2;
   /* Bounded polling also avoids signal-before-blocking-wait cancellation race. */
   poll(NULL,0,20);
  }
  if(control[1]>=0) close(control[1]);
  if(!WIFEXITED(status)) {
   pid_t group=*active_group;
   if(group>0) kill(-group,SIGKILL);
   double reap_until=monotonic()+0.25;
   int child;
   do {while(waitpid(-1,&child,WNOHANG)>0) {} poll(NULL,0,10);} while(monotonic()<reap_until);
   if(active_group[2]) cleanup_owned(root);
  }
  cleanup_root=-1;
  close(root);close(tmp);
  return WIFEXITED(status)?WEXITSTATUS(status):(expired?0:2);
 }
 close(control[1]);signal(SIGTERM,SIG_IGN);signal(SIGINT,SIG_IGN);
 if(prctl(PR_SET_CHILD_SUBREAPER,1)) die("subreaper");
 /* Check controller/deadline before creating the lock. After creation the
  * guardian remains responsive while a separate phase does all blocking I/O. */
 struct pollfd owner_fd={.fd=control[0],.events=POLLIN|POLLHUP};
 if(poll(&owner_fd,1,0)!=0 || monotonic()>=started+(double)ttl) return 2;
 /* Under the inode lock, reject a pre-existing directory before publishing
  * ownership. Publish BEFORE the child mkdir: even death inside/after mkdir
  * is recoverable, without risking deletion of another helper's snapshot. */
 if(provisioning) {
  /* Short inode-scoped exclusion covers absent-name claim through identity
   * publication. It is released before the lease, not a global lease lock. */
  if(flock(root,LOCK_EX|LOCK_NB)) die("provision namespace exclusion");
  if(fstatat(root,r+5,&st,AT_SYMLINK_NOFOLLOW)==0 || errno!=ENOENT) die("existing provision directory");
 } else if(fstatat(root,"runner.lock",&st,AT_SYMLINK_NOFOLLOW)==0 || errno!=ENOENT) die("existing runner lock");
 cleanup_root=root;active_group[2]=1;
 struct preparation prep={root,r,snap,cfg,cert,key};
 double deadline=started+(double)ttl;
 double startup=started+2.0;if(startup>deadline) startup=deadline;
 int rc=2,owned_runtime=-1;
 int prepared=monotonic()<startup?phase(snap,-1,control[0],startup,&prep):2;
 if(provisioning) {
  if(prepared==0) {
   owned_runtime=private_dir(root,r+5);
   if(!same_entry(root,r+5,&provision_owner->dir) || flock(owned_runtime,LOCK_EX|LOCK_NB)) prepared=2;
  }
  flock(root,LOCK_UN);
 }
 if(prepared==0 && monotonic()<startup && phase(snap,1,control[0],startup,NULL)==0 && monotonic()<deadline) {
  struct pollfd fd={.fd=control[0],.events=POLLIN|POLLHUP};
  if(poll(&fd,1,0)==0) {active_group[1]=1;rc=phase(snap,0,control[0],deadline,NULL);}
 }
 close(control[0]);
 on_exit_cleanup();cleanup_root=-1;
 if(owned_runtime>=0) close(owned_runtime);
 close(root);close(tmp);return rc;
}
