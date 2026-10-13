/* Test-only loopback chunk emitter; not packaged or installed. */
#define _POSIX_C_SOURCE 200809L
#include <arpa/inet.h>
#include <errno.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>
static void expired(int n) { (void)n; kill(-getpid(), SIGKILL); _exit(1); }
static int emit(int fd,const char *buf,size_t len) {
 while(len) { ssize_t n=send(fd,buf,len,MSG_NOSIGNAL); if(n<0&&errno==EINTR)continue; if(n<=0)return -1;buf+=n;len-=(size_t)n; } return 0;
}
static void serve(int fd,const char *marker) {
 struct timeval tv={5,0};setsockopt(fd,SOL_SOCKET,SO_RCVTIMEO,&tv,sizeof(tv));setsockopt(fd,SOL_SOCKET,SO_SNDTIMEO,&tv,sizeof(tv));
 char req[2048];ssize_t n=recv(fd,req,sizeof(req)-1,0);if(n<=0)return;req[n]=0;
 char line[512],chunk[600];
 if(strncmp(req,"GET /hold ",10)) { int len=snprintf(line,sizeof(line),"HTTP/1.1 200 OK\r\nContent-Length: %zu\r\nConnection: close\r\n\r\n%s",strlen(marker),marker);emit(fd,line,(size_t)len);return; }
 const char *header="HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nTransfer-Encoding: chunked\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n";
 if(emit(fd,header,strlen(header)))return;
 for(int i=1;i<=91;i++) {
  struct timespec now;clock_gettime(CLOCK_MONOTONIC,&now);
  int len=snprintf(line,sizeof(line),"tick %d %.6f %s\n",i,now.tv_sec+now.tv_nsec/1e9,marker);
  int count=snprintf(chunk,sizeof(chunk),"%x\r\n%s\r\n",len,line);
  if(emit(fd,chunk,(size_t)count))return;
  struct timespec delay={2,0};while(nanosleep(&delay,&delay)<0&&errno==EINTR){}
 }
 emit(fd,"0\r\n\r\n",5);
}
int main(int argc,char **argv) {
 if(argc!=3||strlen(argv[2])>200)return 2;
 if(getpgrp()!=getpid()&&setsid()<0)return 3;
 signal(SIGPIPE,SIG_IGN);signal(SIGCHLD,SIG_IGN);signal(SIGALRM,expired);signal(SIGTERM,expired);alarm(210);
 int fd=socket(AF_INET,SOCK_STREAM,0);if(fd<0)return 4;
 struct sockaddr_in addr={.sin_family=AF_INET,.sin_port=htons((unsigned short)atoi(argv[1]))};inet_pton(AF_INET,"127.0.0.1",&addr.sin_addr);
 if(bind(fd,(struct sockaddr*)&addr,sizeof(addr))||listen(fd,8))return 5;
 fprintf(stderr,"BACKEND_READY pid=%ld group=%ld source_stream_seconds=182 independent_guard_seconds=210\n",(long)getpid(),(long)getpgrp());fflush(stderr);
 for(;;) { int c=accept(fd,NULL,NULL);if(c<0){if(errno==EINTR)continue;return 6;}pid_t p=fork();if(p==0){close(fd);signal(SIGTERM,SIG_DFL);signal(SIGALRM,SIG_DFL);alarm(190);serve(c,argv[2]);close(c);_exit(0);}close(c); }
}
