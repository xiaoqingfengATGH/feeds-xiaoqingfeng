#define _GNU_SOURCE
#include "renewable-guard.h"
#include <assert.h>
#include <arpa/inet.h>
#include <poll.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/prctl.h>
#include <sys/socket.h>
#include <sys/wait.h>
#include <time.h>
#include <fcntl.h>
#include <errno.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <unistd.h>
#include <dirent.h>
static struct stat foreign_objects[5];
static void role_fds(pid_t pid,int expected) {
 char path[128];snprintf(path,sizeof(path),"/proc/%d/fd",pid);DIR *d=opendir(path);assert(d);struct dirent *e;int count=0;
 while((e=readdir(d))) {if(e->d_name[0]=='.')continue;
  char link[512];snprintf(link,sizeof(link),"%s/%s",path,e->d_name);struct stat st;assert(!stat(link,&st));count++;
  for(int i=0;i<5;i++)assert(st.st_dev!=foreign_objects[i].st_dev || st.st_ino!=foreign_objects[i].st_ino);
 }
 closedir(d);assert(count==expected);printf("FD role pid=%d count=%d: every foreign inode absent\n",pid,count);
}
static int foreign_fds[5];
static void foreign_setup(void) {
 foreign_fds[0]=socket(AF_INET,SOCK_STREAM|SOCK_CLOEXEC,0);assert(foreign_fds[0]>=0);
 struct sockaddr_in a={.sin_family=AF_INET,.sin_addr.s_addr=htonl(INADDR_LOOPBACK)};
 assert(!bind(foreign_fds[0],(void*)&a,sizeof(a)));assert(!listen(foreign_fds[0],2));
 int pair[2];assert(!socketpair(AF_UNIX,SOCK_STREAM|SOCK_CLOEXEC,0,pair));foreign_fds[1]=pair[0];foreign_fds[2]=pair[1];
 foreign_fds[3]=open("/dev/null",O_RDWR|O_CLOEXEC);assert(foreign_fds[3]>=0);
 foreign_fds[4]=socket(AF_UNIX,SOCK_SEQPACKET|SOCK_CLOEXEC,0);assert(foreign_fds[4]>=0);
 for(int i=0;i<5;i++)assert(!fstat(foreign_fds[i],&foreign_objects[i]));
}
static long long ms(void) { struct timespec t;assert(!clock_gettime(CLOCK_MONOTONIC,&t));return (long long)t.tv_sec*1000+t.tv_nsec/1000000; }
static void pause_ms(int n) {poll(NULL,0,n);}
static void stream(int report) {
 if(foreign_fds[0]) for(int i=0;i<5;i++) {errno=0;assert(fcntl(foreign_fds[i],F_GETFD)==-1 && errno==EBADF);}
 int s=socket(AF_INET,SOCK_STREAM,0);assert(s>=0);
 struct sockaddr_in a={.sin_family=AF_INET,.sin_addr.s_addr=htonl(INADDR_LOOPBACK)};
 assert(!bind(s,(void*)&a,sizeof(a)));assert(!listen(s,4));socklen_t l=sizeof(a);assert(!getsockname(s,(void*)&a,&l));
 struct {pid_t pid;unsigned port;} info={getpid(),ntohs(a.sin_port)};
 assert(write(report,&info,sizeof(info))==sizeof(info));close(report);
 int c=accept(s,NULL,NULL);assert(c>=0);
 for(;;) {assert(send(c,"tick\n",5,MSG_NOSIGNAL)==5);pause_ms(20);}
}
static int connect_port(unsigned port) {
 int s=socket(AF_INET,SOCK_STREAM,0);struct sockaddr_in a={.sin_family=AF_INET,.sin_addr.s_addr=htonl(INADDR_LOOPBACK),.sin_port=htons(port)};
 if(connect(s,(void*)&a,sizeof(a))) {close(s);return -1;}return s;
}
int main(int argc,char **argv) {
 assert(argc==2);assert(!prctl(PR_SET_CHILD_SUBREAPER,1));
 if(!strcmp(argv[1],"foreign-fd")) foreign_setup();
 int p[2];assert(!pipe(p)); struct hp_guard g;
 long long start=ms();assert(!hp_guard_start(&g,7,9,!strcmp(argv[1],"temporary")?800:0,stream,p[1]));close(p[1]);
 struct {pid_t pid;unsigned port;} info;
 struct pollfd f={p[0],POLLIN,0};assert(poll(&f,1,1000)==1);assert(read(p[0],&info,sizeof(info))==sizeof(info));close(p[0]);
 int s=connect_port(info.port);assert(s>=0);char b[128];assert(recv(s,b,sizeof(b),0)>0);
 if(!strcmp(argv[1],"foreign-fd")) {
  char path[128];snprintf(path,sizeof(path),"/proc/%d/task/%d/children",g.pid,g.pid);
  FILE *fp=fopen(path,"r");assert(fp);int w=0;assert(fscanf(fp,"%d",&w)==1);fclose(fp);
  /* Each supervisor now retains an additional provider pidfd for EMFILE-safe cleanup. */
  role_fds(g.pid,4);role_fds(w,3);role_fds(info.pid,2);
  for(int i=0;i<5;i++){struct stat st;assert(!fstat(foreign_fds[i],&st));assert(st.st_dev==foreign_objects[i].st_dev && st.st_ino==foreign_objects[i].st_ino);}
  struct sockaddr_in a;socklen_t n=sizeof(a);assert(!getsockname(foreign_fds[0],(void*)&a,&n));assert(a.sin_family==AF_INET);
  assert(write(foreign_fds[1],"x",1)==1);char c;assert(read(foreign_fds[2],&c,1)==1 && c=='x');
 }
 if(!strcmp(argv[1],"renew")) {
  for(int i=0;i<8;i++) {pause_ms(150);assert(!hp_guard_send(&g,1));assert(recv(s,b,sizeof(b),MSG_DONTWAIT)>0);assert(!kill(info.pid,0));}
  assert(ms()-start>HP_WINDOW_MS*2);
 } else if(!strcmp(argv[1],"temporary")) {
  for(int i=0;i<5;i++) {pause_ms(150);assert(!hp_guard_send(&g,1));}
  pause_ms(300);assert(connect_port(info.port)<0);assert(ms()-start<1400);
 } else if(!strncmp(argv[1],"watchdog-",9)) {
  char path[128];snprintf(path,sizeof(path),"/proc/%d/task/%d/children",g.pid,g.pid);
  FILE *fp=fopen(path,"r");assert(fp);int w=0;assert(fscanf(fp,"%d",&w)==1);fclose(fp);
  assert(!kill(w,strstr(argv[1],"stop")?SIGSTOP:SIGKILL));
 } else if(!strncmp(argv[1],"guardian-",9)) {
  assert(!kill(g.pid,strstr(argv[1],"stop")?SIGSTOP:SIGKILL));
 } else if(!strncmp(argv[1],"controller-",11)) {
  pid_t c=fork();assert(c>=0);
  if(!c) {for(;;) {hp_guard_send(&g,1);pause_ms(50);}}
  close(g.fd);g.fd=-1;pause_ms(100);
  assert(!kill(c,strstr(argv[1],"stop")?SIGSTOP:SIGKILL));
  pause_ms(750);assert(connect_port(info.port)<0);kill(c,SIGKILL);
 } else if(!strcmp(argv[1],"stop")) {
  assert(!hp_guard_send(&g,2));(void)hp_guard_send(&g,1);
 } else if(!strcmp(argv[1],"flood")) {
  assert(!kill(g.pid,SIGSTOP));for(int i=0;i<33;i++) assert(!hp_guard_send(&g,1));assert(!kill(g.pid,SIGCONT));
 } else if(!strcmp(argv[1],"queued-stop")) {
  assert(!kill(g.pid,SIGSTOP));assert(!hp_guard_send(&g,1));assert(!hp_guard_send(&g,2));assert(!hp_guard_send(&g,1));assert(!kill(g.pid,SIGCONT));
 } else if(!strcmp(argv[1],"stale-gen")) {g.generation++;assert(!hp_guard_send(&g,1));}
 else if(!strcmp(argv[1],"stale-epoch")) {g.epoch++;assert(!hp_guard_send(&g,1));}
 else if(!strcmp(argv[1],"replay")) {assert(!hp_guard_send(&g,1));pause_ms(50);g.sequence--;assert(!hp_guard_send(&g,1));}
 else if(!strcmp(argv[1],"auth")) {g.token[0]^=1;assert(!hp_guard_send(&g,1));}
 else if(!strcmp(argv[1],"short")) {assert(send(g.fd,"x",1,MSG_NOSIGNAL)==1);}
 else assert(!strcmp(argv[1],"expiry") || !strcmp(argv[1],"foreign-fd"));
 long long closing=ms();
 if(strcmp(argv[1],"foreign-fd") && strcmp(argv[1],"expiry") && strcmp(argv[1],"renew") && strcmp(argv[1],"temporary") && strncmp(argv[1],"controller-",11)) {
  pause_ms(350);assert(connect_port(info.port)<0);
 } else pause_ms(850);
 assert(ms()-closing<1500);
 while(recv(s,b,sizeof(b),MSG_DONTWAIT)>0) {}
 assert(recv(s,b,sizeof(b),0)==0);close(s);assert(connect_port(info.port)<0);close(g.fd);
 long long until=ms()+700;do {while(waitpid(-1,NULL,WNOHANG)>0){} pause_ms(10);}while(ms()<until);
 char path[80];snprintf(path,sizeof(path),"/proc/%d",info.pid);assert(access(path,F_OK));
 snprintf(path,sizeof(path),"/proc/%d",g.pid);assert(access(path,F_OK));
 assert(waitpid(-1,NULL,WNOHANG)==-1);
 if(foreign_fds[0]) for(int i=0;i<5;i++) {struct stat st;assert(!fstat(foreign_fds[i],&st));assert(st.st_dev==foreign_objects[i].st_dev && st.st_ino==foreign_objects[i].st_ino);close(foreign_fds[i]);}
 printf("PASS %s: stream EOF, listener refused, owned PIDs absent\n",argv[1]);return 0;
}
