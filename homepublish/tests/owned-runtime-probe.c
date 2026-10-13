#define _GNU_SOURCE
#include "renewable-guard.h"
#include "owned-runtime.h"
#include <assert.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>
#include <poll.h>
static struct hp_owned_runtime *r;
static int step;
static void provision(int fd) {
 for(int i=0;i<step;i++)assert(!hp_owned_file(r,(unsigned)i,"secret",6));
 assert(write(fd,"R",1)==1);close(fd);
 if(step<4)_exit(23); /* fixed fault points after each native-owned file */
 for(;;)pause();
}
int main(int argc,char **argv) {
 assert(argc==3);int root=open(argv[1],O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC);assert(root>=0);
 r=hp_owned_prepare(root);assert(r);int d=hp_owned_dirfd(r);const char *mode=argv[2];struct stat s,t;
 if(!strncmp(mode,"startup",7) || !strcmp(mode,"stop") || !strcmp(mode,"invalid")) {
  step=!strcmp(mode,"stop")?4:mode[7]-'0';
  struct hp_guard g;int p[2];assert(!pipe(p));hp_guard_bind_owned_test(r);
  int invalid=!strcmp(mode,"invalid");int rc=hp_guard_start(&g,invalid?0:7,9,0,provision,p[1]);close(p[1]);
  if(invalid) {assert(rc==-1);assert(!fstatat(d,"key.pem",&s,AT_SYMLINK_NOFOLLOW) && s.st_size==0);assert(!hp_owned_cleanup(r));}
  else {
   assert(!rc);char ready;assert(read(p[0],&ready,1)==1);
   if(step==4)assert(!hp_guard_send(&g,2));
   close(g.fd);
   for(int i=0;i<500;i++){if(fstatat(root,"runtime",&s,AT_SYMLINK_NOFOLLOW))break;poll(NULL,0,5);}
   assert(fstatat(root,"runtime",&s,AT_SYMLINK_NOFOLLOW)==-1);
   while(waitpid(-1,NULL,WNOHANG)>0){} /* no fallback cleanup before assertion */
  }
  close(p[0]);
 } else {
  assert(!hp_owned_file(r,1,"secret",6));assert(!fstatat(d,"key.pem",&s,AT_SYMLINK_NOFOLLOW));
  if(!strcmp(mode,"pinned")) {
   int found=0;for(int fd=0;fd<256;fd++){struct stat u;if(!fstat(fd,&u) && S_ISREG(u.st_mode) && u.st_dev==s.st_dev && u.st_ino==s.st_ino)found=1;}
   assert(found && "owned inode must remain FD-pinned until cleanup");assert(!hp_owned_cleanup(r));
  }
  else if(!strcmp(mode,"clean")){assert(!hp_owned_cleanup(r));assert(!hp_owned_cleanup(r));}
  else if(!strcmp(mode,"readonly")){assert(!fchmod(d,0500));assert(hp_owned_cleanup(r)==1);assert(!fchmod(d,0700));assert(!hp_owned_cleanup(r));}
  else if(!strcmp(mode,"hardlink")){assert(!linkat(d,"key.pem",root,"foreign",0));assert(hp_owned_cleanup(r)==1);assert(!fstatat(root,"foreign",&t,0));assert(s.st_ino==t.st_ino);}
  else if(!strcmp(mode,"symlink") || !strcmp(mode,"replacement")) {
   assert(!renameat(d,"key.pem",root,"original"));
   int f=openat(root,"foreign",O_CREAT|O_EXCL|O_WRONLY,0600);assert(f>=0);assert(write(f,"foreign",7)==7);close(f);
   if(!strcmp(mode,"symlink"))assert(!symlinkat("../foreign",d,"key.pem"));
   else {f=openat(d,"key.pem",O_CREAT|O_EXCL|O_WRONLY,0600);assert(f>=0);close(f);}
   assert(!fstatat(d,"key.pem",&t,AT_SYMLINK_NOFOLLOW));assert(hp_owned_cleanup(r)==1);
   struct stat u;assert(!fstatat(d,"key.pem",&u,AT_SYMLINK_NOFOLLOW));assert(t.st_ino==u.st_ino);
   assert(!fstatat(root,"original",&u,0));assert(s.st_ino==u.st_ino);
  } else if(!strcmp(mode,"directory")) {
   assert(!renameat(root,"runtime",root,"original"));assert(!mkdirat(root,"runtime",0700));assert(!fstatat(root,"runtime",&t,0));
   assert(hp_owned_cleanup(r)==1);struct stat u;assert(!fstatat(root,"runtime",&u,0));assert(t.st_ino==u.st_ino);
  } else if(!strcmp(mode,"foreign-temp")) {
   int f=openat(d,"body/foreign",O_CREAT|O_EXCL|O_WRONLY,0600);assert(f>=0);close(f);assert(!fstatat(d,"body/foreign",&t,0));
   assert(hp_owned_cleanup(r)==1);struct stat u;assert(!fstatat(d,"body/foreign",&u,0));assert(t.st_ino==u.st_ino);
  } else assert(0);
 }
 hp_owned_release(r);close(root);printf("PASS native ownership %s\n",mode);return 0;
}
