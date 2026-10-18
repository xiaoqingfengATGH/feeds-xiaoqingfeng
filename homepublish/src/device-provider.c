/* SPDX-License-Identifier: Apache-2.0
 * Fixed device-test broker. Root owns journal/socket; provider is nobody.
 * No client executable/path/port. Production activation remains unavailable. */
#define _GNU_SOURCE
#include <lua.h>
#include <lauxlib.h>
#include <errno.h>
#include <fcntl.h>
#include <grp.h>
#include <poll.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/prctl.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <sys/wait.h>
#include <unistd.h>
#include "renewable-guard.h"
#include "owned-runtime.h"
#define ROOT "/tmp/homepublish-device"
#define SOCK "/var/run/homepublish-controller.sock"
extern void hp_guard_bind_owned_device(struct hp_owned_runtime *);
extern int hp_guard_start_device(struct hp_guard *,uint64_t,uint64_t,unsigned,void (*)(int),int);
static int broker=-1,server=-1,peer=-1;
static pid_t owner;
static struct hp_owned_runtime *runtime;
static char *configuration,*certificate,*key;
static size_t configuration_len,certificate_len,key_len;
static int load(const char *path,char **value,size_t *len) {
 int fd=open(path,O_RDONLY|O_NOFOLLOW|O_CLOEXEC);struct stat st;
 if(fd<0)return -1;
 if(fstat(fd,&st)||!S_ISREG(st.st_mode)||st.st_uid!=0||st.st_nlink!=1||st.st_size<1||st.st_size>65536){close(fd);return -1;}
 *len=(size_t)st.st_size;*value=malloc(*len);if(!*value){close(fd);return -1;}
 ssize_t n=read(fd,*value,*len);close(fd);return n==(ssize_t)*len?0:-1;
}
static void provider(int fd) {
 close(fd);
 if(hp_owned_file(runtime,0,certificate,certificate_len)||hp_owned_file(runtime,1,key,key_len)||hp_owned_file(runtime,2,configuration,configuration_len)||hp_owned_file(runtime,3,"",0))_exit(127);
 char *argv[]={"/usr/sbin/nginx","-p",ROOT "/runtime/","-c","nginx.conf",NULL};
 char *env[]={"PATH=/usr/bin:/bin","LANG=C","OPENSSL_CONF=/dev/null","OPENSSL_MODULES=" ROOT "/runtime","OPENSSL_ENGINES=" ROOT "/runtime",NULL};
 execve(argv[0],argv,env);_exit(127);
}
static int stop_native(void) {
 if(broker>=0){(void)send(broker,"s",1,MSG_NOSIGNAL);close(broker);broker=-1;}
 if(owner>0){for(int i=0;i<400;i++){int rc=waitpid(owner,NULL,WNOHANG);if(rc==owner){owner=0;break;}poll(NULL,0,5);}}
 return owner==0 && access(ROOT "/runtime",F_OK)<0 && errno==ENOENT;
}
static int start(lua_State *L) {
 if(geteuid()!=0||owner>0){lua_pushboolean(L,0);return 1;}
 configuration=(char *)luaL_checklstring(L,1,&configuration_len);
 uint64_t gen=(uint64_t)luaL_checknumber(L,2);unsigned ttl=(unsigned)luaL_checknumber(L,3);
 certificate=NULL;key=NULL;
 if(configuration_len>65536||load("/etc/homepublish/device-test/cert.pem",&certificate,&certificate_len)||load("/etc/homepublish/device-test/key.pem",&key,&key_len)){free(certificate);free(key);lua_pushboolean(L,0);return 1;}
 struct stat st;
 if(mkdir(ROOT,0700)<0 && errno!=EEXIST)goto bad;
 if(lstat(ROOT,&st)||!S_ISDIR(st.st_mode)||st.st_nlink<2||(st.st_uid!=0&&st.st_uid!=65534)||chmod(ROOT,0700)||chown(ROOT,65534,65534))goto bad;
 int pair[2];if(socketpair(AF_UNIX,SOCK_SEQPACKET|SOCK_CLOEXEC,0,pair))goto bad;
 owner=fork();
 if(owner==0){
  close(pair[0]);if(server>=0)close(server);if(peer>=0)close(peer);
  if(setgroups(0,NULL)||setgid(65534)||setuid(65534)||prctl(PR_SET_CHILD_SUBREAPER,1))_exit(126);
  int root=open(ROOT,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC);if(root<0)_exit(126);
  runtime=hp_owned_prepare(root);close(root);if(!runtime)_exit(126);
  hp_guard_bind_owned_device(runtime);struct hp_guard g;int channel[2];
  if(pipe(channel))_exit(126);
  int rc=hp_guard_start_device(&g,gen,gen,ttl,provider,channel[1]);close(channel[0]);close(channel[1]);
  char ready=rc?'e':'y';(void)send(pair[1],&ready,1,MSG_NOSIGNAL);
  if(!rc){
   for(;;){struct pollfd p={pair[1],POLLIN,0};int n=poll(&p,1,150);char op;
    if(n<=0||recv(pair[1],&op,1,0)!=1||op!='r'||hp_guard_send(&g,1))break;
   }
   (void)hp_guard_send(&g,2);close(g.fd);
  }
  close(pair[1]);
  for(int i=0;i<350;i++){while(waitpid(-1,NULL,WNOHANG)>0){}if(access(ROOT "/runtime",F_OK)<0&&errno==ENOENT)_exit(0);poll(NULL,0,5);}
  _exit(125);
 }
 close(pair[1]);broker=pair[0];free(certificate);free(key);
 if(owner<0){close(broker);broker=-1;owner=0;lua_pushboolean(L,0);return 1;}
 struct pollfd p={broker,POLLIN,0};char ready=0;
 int ok=poll(&p,1,1500)>0&&recv(broker,&ready,1,0)==1&&ready=='y';
 if(!ok)(void)stop_native();
 lua_pushboolean(L,ok);return 1;
 bad:free(certificate);free(key);lua_pushboolean(L,0);return 1;
}
static int renew(lua_State *L){lua_pushboolean(L,broker>=0&&send(broker,"r",1,MSG_NOSIGNAL)==1);return 1;}
static int stop(lua_State *L){lua_pushboolean(L,stop_native());return 1;}
static int listen_native(lua_State *L){
 if(geteuid()!=0)return luaL_error(L,"root controller required");
 struct stat old;
 if(lstat(SOCK,&old)==0){
  int probe=socket(AF_UNIX,SOCK_SEQPACKET|SOCK_CLOEXEC,0);struct sockaddr_un check={.sun_family=AF_UNIX};strcpy(check.sun_path,SOCK);
  int connected=probe>=0 && connect(probe,(struct sockaddr *)&check,sizeof(check))==0;if(probe>=0)close(probe);
  if(connected||!S_ISSOCK(old.st_mode)||old.st_uid!=0||unlink(SOCK))return luaL_error(L,"controller socket busy");
 }
 server=socket(AF_UNIX,SOCK_SEQPACKET|SOCK_CLOEXEC,0);struct sockaddr_un a={.sun_family=AF_UNIX};strcpy(a.sun_path,SOCK);
 if(server<0||bind(server,(struct sockaddr *)&a,sizeof(a))||chmod(SOCK,0600)||listen(server,4))return luaL_error(L,"controller socket unavailable");
 lua_pushboolean(L,1);return 1;
}
static int receive_native(lua_State *L){
 struct pollfd p={server,POLLIN,0};if(poll(&p,1,60)<=0){lua_pushnil(L);return 1;}
 peer=accept4(server,NULL,NULL,SOCK_CLOEXEC);if(peer<0){lua_pushnil(L);return 1;}
 struct ucred cred;socklen_t len=sizeof(cred);
 if(getsockopt(peer,SOL_SOCKET,SO_PEERCRED,&cred,&len)||cred.uid!=0){close(peer);peer=-1;lua_pushnil(L);return 1;}
 p.fd=peer;char buf[262145];
 if(poll(&p,1,80)<=0){close(peer);peer=-1;lua_pushnil(L);return 1;}
 ssize_t n=recv(peer,buf,sizeof(buf),0);if(n<=0||n>=262145){close(peer);peer=-1;lua_pushnil(L);return 1;}
 lua_pushlstring(L,buf,(size_t)n);return 1;
}
static int reply(lua_State *L){size_t n;const char *s=luaL_checklstring(L,1,&n);if(peer>=0){(void)send(peer,s,n,MSG_NOSIGNAL);close(peer);peer=-1;}return 0;}
static int request(lua_State *L){
 if(geteuid()!=0)return luaL_error(L,"root test operation required");
 size_t n;const char *s=luaL_checklstring(L,1,&n);if(n>262144)return luaL_error(L,"request too long");
 int fd=socket(AF_UNIX,SOCK_SEQPACKET|SOCK_CLOEXEC,0);struct sockaddr_un a={.sun_family=AF_UNIX};strcpy(a.sun_path,SOCK);
 if(fd<0||connect(fd,(struct sockaddr *)&a,sizeof(a))||send(fd,s,n,MSG_NOSIGNAL)!=(ssize_t)n){if(fd>=0)close(fd);return luaL_error(L,"controller unavailable");}
 struct pollfd p={fd,POLLIN,0};char buf[262145];
 if(poll(&p,1,5000)<=0){close(fd);return luaL_error(L,"controller timeout");}
 ssize_t k=recv(fd,buf,sizeof(buf),0);close(fd);if(k<=0||k>=262145)return luaL_error(L,"invalid response");lua_pushlstring(L,buf,(size_t)k);return 1;
}
int luaopen_homepublish_device(lua_State *L){
 static const luaL_Reg f[]={{"start",start},{"renew",renew},{"stop",stop},{"listen",listen_native},{"receive",receive_native},{"reply",reply},{"request",request},{NULL,NULL}};
 luaL_register(L,"homepublish_device",f);return 1;
}
