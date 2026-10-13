/* Flat, fixed-name ownership ledger. No recursive sweep or path inference.
 * Same-UID/root concurrent mutation is outside the supervisor trust contract.
 * Empty inode FD anchors exist before fork; secrets are written under guard.
 * Unknown/replaced/hardlinked entries are residuals, never deletion authority. */
#include "owned-runtime.h"
#include <fcntl.h>
static const char *owned_names[]={"cert.pem","key.pem","nginx.conf","nginx.pid"};
struct owned_entry { dev_t dev; ino_t ino; int fd; _Atomic int registered; _Atomic int written; };
struct hp_owned_runtime {
 int parent,dir; dev_t dev; ino_t ino;
 struct owned_entry entries[4];
 struct owned_entry dirs[5];
};
static const char *owned_dirs[]={"body","proxy","fastcgi","uwsgi","scgi"};
static struct hp_owned_runtime *owned_runtime;
struct hp_owned_runtime *hp_owned_prepare(int parentfd) {
 struct stat s,t;
 if(fstat(parentfd,&s) || !S_ISDIR(s.st_mode) || s.st_uid!=geteuid() || (s.st_mode&0777)!=0700) {errno=EPERM;return NULL;}
 struct hp_owned_runtime *r=mmap(NULL,sizeof(*r),PROT_READ|PROT_WRITE,MAP_SHARED|MAP_ANONYMOUS,-1,0);
 if(r==MAP_FAILED)return NULL;
 memset(r,0,sizeof(*r));r->parent=fcntl(parentfd,F_DUPFD_CLOEXEC,3);r->dir=-1;
 for(unsigned i=0;i<4;i++)r->entries[i].fd=-1;
 for(unsigned i=0;i<5;i++)r->dirs[i].fd=-1;
 if(r->parent<0 || mkdirat(r->parent,"runtime",0700))goto bad;
 if(fstatat(r->parent,"runtime",&s,AT_SYMLINK_NOFOLLOW))goto bad;
 r->dev=s.st_dev;r->ino=s.st_ino;
 r->dir=openat(r->parent,"runtime",O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC);
 if(r->dir<0 || fstat(r->dir,&t) || t.st_dev!=s.st_dev || t.st_ino!=s.st_ino || t.st_uid!=geteuid() || (t.st_mode&0777)!=0700)goto bad;
 for(unsigned i=0;i<5;i++) {
  if(mkdirat(r->dir,owned_dirs[i],0700) || fstatat(r->dir,owned_dirs[i],&t,AT_SYMLINK_NOFOLLOW))goto bad;
  r->dirs[i].fd=openat(r->dir,owned_dirs[i],O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC);
  if(r->dirs[i].fd<0 || fstat(r->dirs[i].fd,&s) || s.st_dev!=t.st_dev || s.st_ino!=t.st_ino || s.st_uid!=geteuid() || (s.st_mode&0777)!=0700)goto bad;
  r->dirs[i].dev=t.st_dev;r->dirs[i].ino=t.st_ino;atomic_store(&r->dirs[i].registered,1);
 }
 for(unsigned i=0;i<4;i++) {
  int fd=openat(r->dir,owned_names[i],O_CREAT|O_EXCL|O_RDWR|O_NOFOLLOW|O_CLOEXEC,0600);r->entries[i].fd=fd;
  if(fd<0 || fstat(fd,&t) || !S_ISREG(t.st_mode) || t.st_uid!=geteuid() || t.st_nlink!=1 || t.st_size!=0 || (t.st_mode&0777)!=0600)goto bad;
  r->entries[i].dev=t.st_dev;r->entries[i].ino=t.st_ino;atomic_store(&r->entries[i].registered,1);
 }
 return r;
 bad: /* partial empty-root residual; no secret has yet been written */
 for(unsigned i=0;i<4;i++)if(r->entries[i].fd>=0)close(r->entries[i].fd);
 for(unsigned i=0;i<5;i++)if(r->dirs[i].fd>=0)close(r->dirs[i].fd);
 if(r->dir>=0)close(r->dir);
 if(r->parent>=0)close(r->parent);
 munmap(r,sizeof(*r));return NULL;
}
int hp_owned_dirfd(struct hp_owned_runtime *r) {return r->dir;}
int hp_owned_file(struct hp_owned_runtime *r,unsigned slot,const void *data,size_t len) {
 if(slot>=4 || atomic_load(&r->entries[slot].written)) {errno=EINVAL;return -1;}
 struct stat d,s,t;
 if(fstat(r->dir,&d) || d.st_dev!=r->dev || d.st_ino!=r->ino || d.st_uid!=geteuid() || (d.st_mode&0777)!=0700)return -1;
 struct owned_entry *e=&r->entries[slot];int fd=e->fd;
 if(fstat(fd,&s) || fstatat(r->dir,owned_names[slot],&t,AT_SYMLINK_NOFOLLOW) || !S_ISREG(s.st_mode) || s.st_uid!=geteuid() || s.st_nlink!=1 || (s.st_mode&0777)!=0600 || s.st_dev!=e->dev || s.st_ino!=e->ino || t.st_dev!=s.st_dev || t.st_ino!=s.st_ino)return -1;
 atomic_store(&e->written,1);
 const char *p=data;size_t n=0;
 while(n<len) {ssize_t w=pwrite(fd,p+n,len-n,(off_t)n);if(w<0 && errno==EINTR)continue;if(w<=0)return -1;n+=(size_t)w;}
 return fsync(fd);
}
int hp_owned_cleanup(struct hp_owned_runtime *r) {
 if(!r)return 0;
 int residual=0;struct stat s;
 for(unsigned i=0;i<4;i++) {
  if(!atomic_load_explicit(&r->entries[i].registered,memory_order_acquire))continue;
  if(fstatat(r->dir,owned_names[i],&s,AT_SYMLINK_NOFOLLOW)) {if(errno!=ENOENT)residual=1;continue;}
  if(!S_ISREG(s.st_mode) || s.st_uid!=geteuid() || s.st_nlink!=1 || s.st_dev!=r->entries[i].dev || s.st_ino!=r->entries[i].ino) {residual=1;continue;}
  if(unlinkat(r->dir,owned_names[i],0) && errno!=ENOENT)residual=1;
 }
 for(unsigned i=0;i<5;i++) {
  if(!atomic_load(&r->dirs[i].registered))continue;
  if(fstatat(r->dir,owned_dirs[i],&s,AT_SYMLINK_NOFOLLOW)) {if(errno!=ENOENT)residual=1;continue;}
  if(!S_ISDIR(s.st_mode) || s.st_uid!=geteuid() || s.st_dev!=r->dirs[i].dev || s.st_ino!=r->dirs[i].ino) {residual=1;continue;}
  if(unlinkat(r->dir,owned_dirs[i],AT_REMOVEDIR) && errno!=ENOENT)residual=1;
 }
 if(fstatat(r->parent,"runtime",&s,AT_SYMLINK_NOFOLLOW)) {if(errno!=ENOENT)residual=1;}
 else if(!S_ISDIR(s.st_mode) || s.st_dev!=r->dev || s.st_ino!=r->ino || s.st_uid!=geteuid())residual=1;
 else if(unlinkat(r->parent,"runtime",AT_REMOVEDIR) && errno!=ENOENT)residual=1;
 return residual;
}
void hp_owned_release(struct hp_owned_runtime *r) {
 if(owned_runtime==r)owned_runtime=NULL;
 for(unsigned i=0;i<4;i++)close(r->entries[i].fd);
 for(unsigned i=0;i<5;i++)close(r->dirs[i].fd);
 close(r->dir);close(r->parent);munmap(r,sizeof(*r));
}
#ifdef HP_GUARD_TEST
void hp_guard_bind_owned_test(struct hp_owned_runtime *r) {owned_runtime=r;}
#endif
