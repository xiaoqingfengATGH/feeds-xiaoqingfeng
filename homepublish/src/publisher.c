/* SPDX-License-Identifier: Apache-2.0
 * Fixed-origin publisher. NATMap f8d7996 hev-exec.c passes six positional
 * fields: mapped address, mapped port, ip4p, bind port, mode, bind address.
 * Root is trusted; never setuid. No credentials in argv, UCI or diagnostics.
 */
#define _GNU_SOURCE
#include <sys/stat.h>
#include <sys/file.h>
#include <sys/wait.h>
#include <fcntl.h>
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <arpa/inet.h>
#include <signal.h>
#include <math.h>
#include <errno.h>
#ifndef CURL_PROGRAM
#define CURL_PROGRAM "/usr/bin/curl"
#endif
static int safe(int fd,int dir){struct stat s;return fd>=0&&!fstat(fd,&s)&&s.st_uid==0&&!(s.st_mode&0077)&&(dir?S_ISDIR(s.st_mode):(S_ISREG(s.st_mode)&&s.st_nlink==1));}
static int read_token(int fd,char token[130]) {
 /* A short read is not EOF. Read through EOF or the 129th-byte sentinel;
  * validate the byte count before using a C string (including embedded NUL). */
 size_t used=0;
 while(used<129) {
  ssize_t n=read(fd,token+used,129-used);
  if(n<0) {if(errno==EINTR)continue;return 0;}
  if(!n)break;
  used+=(size_t)n;
 }
 if(used<32 || used>128)return 0;
 for(size_t i=0;i<used;i++) {
  unsigned char c=(unsigned char)token[i];
  if(!((c>='a'&&c<='z')||(c>='A'&&c<='Z')||(c>='0'&&c<='9')||c=='_'||c=='-'||c=='.'))return 0;
 }
 token[used]=0;return 1;
}
static long long millis(void){struct timespec t;if(clock_gettime(CLOCK_REALTIME,&t))return 0;return (long long)t.tv_sec*1000+t.tv_nsec/1000000;}
static double mono(void){struct timespec t;if(clock_gettime(CLOCK_MONOTONIC,&t))return 0;return t.tv_sec+t.tv_nsec/1e9;}
static int port(const char *s){if(!*s)return 0;for(const char *p=s;*p;p++)if(*p<'0'||*p>'9')return 0;long n=strtol(s,NULL,10);return n>=1024&&n<=65535?(int)n:0;}
static int ip(const char *s){struct in_addr a;char b[INET_ADDRSTRLEN];if(inet_pton(AF_INET,s,&a)!=1||!inet_ntop(AF_INET,&a,b,sizeof b)||strcmp(s,b))return 0;unsigned n=ntohl(a.s_addr)>>24;return n>0&&n<224&&n!=127;}
static int post(const char *path,const char *token,const char *json){
 int in[2],out[2];if(pipe(in)||pipe(out))return 2;
 pid_t p=fork();if(p<0)return 2;
 if(!p){
  dup2(in[0],0);dup2(out[1],1);int null=open("/dev/null",O_WRONLY);if(null>=0)dup2(null,2);
  close(in[0]);close(in[1]);close(out[0]);close(out[1]);
  /* Disable ~/.curlrc and inherited proxy/CA overrides. System trust only. */
  char *env[]={"PATH=/usr/bin:/bin",NULL};
  execle(CURL_PROGRAM,"curl","--disable","--config","-",(char*)NULL,env);_exit(127);
 }
 close(in[0]);close(out[1]);
 FILE *f=fdopen(in[1],"w");if(!f){kill(p,SIGKILL);return 2;}
 fprintf(f,"url = \"https://stun-test.innonext.win/%s\"\nproto = \"=https\"\nproto-redir = \"=https\"\nrequest = \"POST\"\nheader = \"Authorization: Bearer %s\"\nheader = \"Content-Type: application/json\"\ndata = \"",path,token);
 for(const char *q=json;*q;q++){if(*q=='"'||*q=='\\')fputc('\\',f);fputc(*q,f);}
 fprintf(f,"\"\nmax-time = 2\nconnect-timeout = 1\nsilent\noutput = \"/dev/null\"\nwrite-out = \"%%{http_code}\"\n");
 int failed=fclose(f);char code[8]={0};ssize_t n=read(out[0],code,7);close(out[0]);int status;
 if(waitpid(p,&status,0)!=p)return 2;
 return !failed&&n==3&&!strcmp(code,"204")&&WIFEXITED(status)&&!WEXITSTATUS(status)?0:2;
}
int main(int argc,char **argv){
 signal(SIGPIPE,SIG_IGN);
 int begin=argc==3&&!strcmp(argv[1],"--begin");
 if(geteuid()!=0||(!begin&&argc!=7))return 2;
 const char *r=begin?argv[2]:getenv("HOMEPUBLISH_RUNTIME");
 if(!r||strncmp(r,"/tmp/homepublish-",17)||strlen(r)>200)return 2;
 for(const char *q=r+17;*q;q++)if(!((*q>='a'&&*q<='z')||(*q>='A'&&*q<='Z')||(*q>='0'&&*q<='9')||*q=='-'))return 2;
 int d=open(r,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC);if(!safe(d,1))return 2;
 int s=openat(d,"session",O_RDWR|O_NOFOLLOW|O_CLOEXEC|O_NONBLOCK);
 if(!safe(s,0)||flock(s,LOCK_EX|LOCK_NB))return 2;
 char raw[256]={0},nonce[33]={0},tail;long long gen,expires;double deadline;unsigned bind;unsigned long long seq;
 ssize_t n=read(s,raw,sizeof raw-1);if(n<=0||n>=255||sscanf(raw,"%lld %32s %lld %lf %u %llu %c",&gen,nonce,&expires,&deadline,&bind,&seq,&tail)!=6)return 2;
 if(!isfinite(deadline)||gen<=0||gen>9007199254740991LL||expires>9007199254740991LL||strlen(nonce)!=32||strspn(nonce,"0123456789abcdef")!=32||expires<=millis()||expires>millis()+120000||deadline<=mono()||deadline>mono()+120||bind<1024||bind>65535||seq>=9007199254740991ULL)return 2;
 int t=openat(d,"router.token",O_RDONLY|O_NOFOLLOW|O_CLOEXEC|O_NONBLOCK);if(!safe(t,0))return 2;
 char token[130]={0};int valid=read_token(t,token);close(t);
 if(!valid)return 2;
 char json[512];
 if(begin)snprintf(json,sizeof json,"{\"generation\":%lld,\"session\":\"%s\",\"expiresAt\":%lld}",gen,nonce,expires);
 else {
  if(!ip(argv[1])||!port(argv[2])||port(argv[4])!=(int)bind||strcmp(argv[5],"tcp"))return 2;
  struct in_addr local;if(inet_pton(AF_INET,argv[6],&local)!=1)return 2;
  /* Sequence reserved before request; failed requests cannot reuse a number. */
  seq++;int len=snprintf(raw,sizeof raw,"%lld %s %lld %.9f %u %llu\n",gen,nonce,expires,deadline,bind,seq);
  if(pwrite(s,raw,(size_t)len,0)!=len||ftruncate(s,len)||fsync(s))return 2;
  snprintf(json,sizeof json,"{\"generation\":%lld,\"session\":\"%s\",\"expiresAt\":%lld,\"sequence\":%llu,\"mappedIP\":\"%s\",\"port\":%d}",gen,nonce,expires,seq,argv[1],port(argv[2]));
 }
 int result=post(begin?"session":"lease",token,json);memset(token,0,sizeof token);close(s);close(d);return result;
}
