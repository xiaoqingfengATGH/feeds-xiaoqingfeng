/* Link-time fault injection only; never installed or used by production. */
#define _GNU_SOURCE
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <stdarg.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#ifndef TRACE_PATH
#define TRACE_PATH "/tmp/token-io-log"
#endif
ssize_t __real_read(int,void *,size_t);
int __real_openat(int,const char *,int,...);
static void trace(const char *s) {
 int f=open(TRACE_PATH,O_WRONLY|O_CREAT|O_APPEND,0600);
 if(f>=0) { (void)write(f,s,strlen(s));close(f); }
}
ssize_t __wrap_read(int fd,void *buf,size_t count) {
#ifndef NO_READ_INJECTION
 char proc[64],path[512];snprintf(proc,sizeof proc,"/proc/self/fd/%d",fd);
 ssize_t n=readlink(proc,path,sizeof path-1);
 int token=0;
 if(n>=0) {path[n]=0;size_t len=strlen(path);token=len>=13&&!strcmp(path+len-13,"/router.token");}
 /* Minimal chroot has no proc mount: match the actual source inode instead. */
 struct stat file,source;
 if(!fstat(fd,&file)&&!stat("/etc/homedirect/router.token",&source)&&file.st_dev==source.st_dev&&file.st_ino==source.st_ino)token=1;
 if(token) {
#ifndef NO_EINTR
  static unsigned calls;
  if(!(calls++%2)) {trace("interrupt\n");errno=EINTR;return -1;}
#endif
  if(count>32)count=32;
  n=__real_read(fd,buf,count);trace(n==0?"eof\n":n>0?"short\n":"error\n");return n;
 }
#endif
 return __real_read(fd,buf,count);
}
int __wrap_openat(int fd,const char *path,int flags,...) {
 mode_t mode=0;
 if(flags&O_CREAT) {va_list ap;va_start(ap,flags);mode=va_arg(ap,int);va_end(ap);}
 if((flags&O_CREAT)&&!strcmp(path,"router.token"))trace("snapshot\n");
 return __real_openat(fd,path,flags,mode);
}
