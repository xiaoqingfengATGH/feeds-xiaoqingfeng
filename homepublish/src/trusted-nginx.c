#define _GNU_SOURCE
#include "trusted-nginx.h"
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/mman.h>
#include <unistd.h>
#if defined(HP_GUARD_TEST) && defined(HP_TRUST_PROFILE_HEADER)
/* Host acceptance only: target hashing/installation manifest is still gated. */
extern unsigned char *SHA256(const unsigned char *,size_t,unsigned char *);
struct hp_trust_entry { const char *source,*name,*sha256; };
#include HP_TRUST_PROFILE_HEADER
#define COUNT (sizeof(hp_trust_entries)/sizeof(hp_trust_entries[0]))
/* No symlink at any component, including installation-root ancestors. */
static int source_open(const char *name) {
 int fd=open("/",O_RDONLY|O_DIRECTORY|O_CLOEXEC);char path[4096];
 if(fd<0 || snprintf(path,sizeof(path),"%s/%s",HP_TRUST_ROOT,name)>=(int)sizeof(path)){if(fd>=0)close(fd);errno=EPERM;return -1;}
 char *save,*part=strtok_r(path,"/",&save);
 while(part){char *next=strtok_r(NULL,"/",&save);int n=openat(fd,part,O_RDONLY|O_NOFOLLOW|O_CLOEXEC|(next?O_DIRECTORY:0));close(fd);if(n<0)return -1;fd=n;part=next;}
 return fd;
}
static unsigned char *verified(unsigned i,size_t *len) {
 struct stat before,after;int fd=source_open(hp_trust_entries[i].source);
 if(fd<0)return NULL;
 unsigned char *p=NULL;unsigned char digest[32];char hex[65];
 if(fstat(fd,&before) || !S_ISREG(before.st_mode) || before.st_nlink!=1 || before.st_size<=0 || before.st_size>16777216)goto bad;
 *len=(size_t)before.st_size;p=malloc(*len);if(!p)goto bad;
 size_t n=0;while(n<*len){ssize_t k=read(fd,p+n,*len-n);if(k<0 && errno==EINTR)continue;if(k<=0)goto bad;n+=(size_t)k;}
 if(fstat(fd,&after) || before.st_dev!=after.st_dev || before.st_ino!=after.st_ino || before.st_size!=after.st_size || before.st_mtim.tv_sec!=after.st_mtim.tv_sec || before.st_mtim.tv_nsec!=after.st_mtim.tv_nsec)goto bad;
 SHA256(p,*len,digest);for(unsigned j=0;j<32;j++)snprintf(hex+2*j,3,"%02x",digest[j]);
 if(strcmp(hex,hp_trust_entries[i].sha256))goto bad;
 close(fd);return p;
 bad:close(fd);free(p);errno=EPERM;return NULL;
}
int hp_trusted_nginx_verify(void) {
 if(COUNT!=7){errno=EPERM;return -1;}
 for(unsigned i=0;i<COUNT;i++){size_t n;unsigned char *p=verified(i,&n);if(!p)return -1;free(p);}return 0;
}
int hp_trusted_nginx_exec(struct hp_owned_runtime *r,const char *prefix) {
 if(!r || !prefix){errno=EPERM;return -1;}
 /* Provision only after the native supervision grant. Bytes hashed are exactly
  * bytes copied, not a hash-then-reopen path. Fixed owned slots, no rm -rf. */
 int execfds[2]={-1,-1};
 for(unsigned i=0;i<COUNT;i++){
  size_t n;unsigned char *p=verified(i,&n);if(!p)return -1;
  int rc=hp_owned_file(r,4+i,p,n);
  if(!rc && i<2){
   int fd=memfd_create(i?"hp-nginx":"hp-loader",MFD_ALLOW_SEALING|(i?0:MFD_CLOEXEC));
   if(fd<0 || write(fd,p,n)!=(ssize_t)n || fcntl(fd,F_ADD_SEALS,F_SEAL_SEAL|F_SEAL_SHRINK|F_SEAL_GROW|F_SEAL_WRITE)<0){if(fd>=0)close(fd);rc=-1;}
   else execfds[i]=fd;
  }
  free(p);if(rc)return -1;
  if(fchmodat(hp_owned_dirfd(r),hp_trust_entries[i].name,i<2?0500:0400,0))return -1;
 }
 char loader[4096],exe[4096],libs[4096];
 if(snprintf(libs,sizeof(libs),"%s/runtime",prefix)>=(int)sizeof(libs) || snprintf(loader,sizeof(loader),"/proc/self/fd/%d",execfds[0])>=(int)sizeof(loader) || snprintf(exe,sizeof(exe),"/proc/self/fd/%d",execfds[1])>=(int)sizeof(exe)){errno=EOVERFLOW;return -1;}
 /* A verified private readonly snapshot under the trusted-provider contract,
  * NOT immutable against same-UID/root interference. Target mount gate open. */
 char *argv[]={loader,"--library-path",libs,exe,"-p",libs,"-c","nginx.conf",NULL};
 char *env[]={"PATH=/usr/bin:/bin","LANG=C",NULL};
 execve(loader,argv,env);return -1;
}
#else
int hp_trusted_nginx_verify(void){errno=ENOTSUP;return -1;}
int hp_trusted_nginx_exec(struct hp_owned_runtime *r,const char *prefix){(void)r;(void)prefix;errno=ENOTSUP;return -1;}
#endif
