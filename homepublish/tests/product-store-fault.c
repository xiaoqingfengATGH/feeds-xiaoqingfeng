/* SPDX-License-Identifier: Apache-2.0 */
/* Isolated LD_PRELOAD fault injection; close really releases its fd then EIO. */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <unistd.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <sys/stat.h>
#include <stdio.h>
static int target(int fd) {
 char p[64],name[4096];snprintf(p,sizeof(p),"/proc/self/fd/%d",fd);
 ssize_t n=readlink(p,name,sizeof(name)-1);if(n<0)return 0;name[n]=0;
 size_t len=strlen(name);return len>=10&&!strcmp(name+len-10,"/candidate");
}
static int fault(const char *stage) {const char *v=getenv("HP_FAULT");return v&&!strcmp(v,stage);}
ssize_t write(int fd,const void *buf,size_t n) {
 ssize_t (*real)(int,const void *,size_t)=dlsym(RTLD_NEXT,"write");
 if(target(fd)&&fault("write")){errno=EIO;return -1;}return real(fd,buf,n);
}
int fsync(int fd) {
 int (*real)(int)=dlsym(RTLD_NEXT,"fsync");struct stat st;
 if((target(fd)&&fault("filefsync"))||(fstat(fd,&st)==0&&S_ISDIR(st.st_mode)&&fault("dirfsync"))){errno=EIO;return -1;}return real(fd);
}
int close(int fd) {
 int (*real)(int)=dlsym(RTLD_NEXT,"close");int fail=target(fd)&&fault("close");int result=real(fd);
 if(fail){errno=EIO;return -1;}return result;
}
int renameat(int a,const char *b,int c,const char *d) {
 int (*real)(int,const char *,int,const char *)=dlsym(RTLD_NEXT,"renameat");
 if(fault("rename")){errno=EIO;return -1;}return real(a,b,c,d);
}
