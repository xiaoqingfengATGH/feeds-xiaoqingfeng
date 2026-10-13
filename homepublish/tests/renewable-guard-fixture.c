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
#include <unistd.h>
static long long ms(void) { struct timespec t;assert(!clock_gettime(CLOCK_MONOTONIC,&t));return (long long)t.tv_sec*1000+t.tv_nsec/1000000; }
static void pause_ms(int n) {poll(NULL,0,n);}
static void stream(int report) {
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
 int p[2];assert(!pipe(p)); struct hp_guard g;
 long long start=ms();assert(!hp_guard_start(&g,7,9,0,stream,p[1]));close(p[1]);
 struct {pid_t pid;unsigned port;} info;
 struct pollfd f={p[0],POLLIN,0};assert(poll(&f,1,1000)==1);assert(read(p[0],&info,sizeof(info))==sizeof(info));close(p[0]);
 int s=connect_port(info.port);assert(s>=0);char b[128];assert(recv(s,b,sizeof(b),0)>0);
 assert(!strcmp(argv[1],"expiry"));
 pause_ms(850);assert(ms()-start<1500);
 while(recv(s,b,sizeof(b),MSG_DONTWAIT)>0) {}
 assert(recv(s,b,sizeof(b),0)==0);close(s);assert(connect_port(info.port)<0);close(g.fd);
 long long until=ms()+700;do {while(waitpid(-1,NULL,WNOHANG)>0){} pause_ms(10);}while(ms()<until);
 char path[80];snprintf(path,sizeof(path),"/proc/%d",info.pid);assert(access(path,F_OK));
 snprintf(path,sizeof(path),"/proc/%d",g.pid);assert(access(path,F_OK));
 puts("PASS expiry: stream EOF, listener refused, owned PIDs absent");return 0;
}
