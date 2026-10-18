/* Test-only fixed host adapter. Not part of package; no runtime exec selection. */
#ifndef HP_GUARD_TEST
#error host test build only
#endif
#define main hp_existing_nginx_fixture_main
#include "guardian-nginx-fixture.c"
#undef main
#include <lua.h>
#include <lauxlib.h>
static struct hp_guard controller_guard;
static int live;
static int adapter_start(lua_State *L) {
 const char *config=luaL_checkstring(L,1);
 uint64_t gen=(uint64_t)luaL_checknumber(L,2);
 unsigned temporary=(unsigned)luaL_checknumber(L,3);
 if(live){lua_pushboolean(L,0);return 1;}
 int out=open(HP_NGINX_PREFIX "/nginx.conf",O_WRONLY|O_CREAT|O_TRUNC|O_NOFOLLOW|O_CLOEXEC,0600);
 size_t len=strlen(config);
 if(out<0){lua_pushboolean(L,0);return 1;}
 ssize_t n=write(out,config,len);int closed=close(out);
 if(n!=(ssize_t)len || closed || hp_trusted_nginx_verify()){lua_pushboolean(L,0);return 1;}
 int root=open(HP_NGINX_PREFIX,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC);
 if(root<0){lua_pushboolean(L,0);return 1;}
 runtime=hp_owned_prepare(root);close(root);
 if(!runtime){lua_pushboolean(L,0);return 1;}
 hp_guard_bind_owned_test(runtime);
 int channel[2];if(pipe(channel)){lua_pushboolean(L,0);return 1;}
 int rc=hp_guard_start_private_test(&controller_guard,gen,gen,temporary,nginx_provider,channel[1]);
 close(channel[0]);close(channel[1]);
 if(rc)fprintf(stderr,"controller adapter start errno=%d\n",errno);
 live=rc==0;lua_pushboolean(L,live);return 1;
}
static int adapter_renew(lua_State *L) {
 lua_pushboolean(L,live && hp_guard_send(&controller_guard,1)==0);return 1;
}
static int adapter_stop(lua_State *L) {
 if(live){(void)hp_guard_send(&controller_guard,2);close(controller_guard.fd);live=0;}
 for(int i=0;i<300;i++) {
  pid_t observed;do {observed=waitpid(-1,NULL,WNOHANG);} while(observed>0);
  if(observed<0 && errno==ECHILD && access(HP_NGINX_PREFIX "/runtime",F_OK)!=0 && errno==ENOENT) {
   if(runtime){hp_owned_release(runtime);runtime=NULL;}
   lua_pushboolean(L,1);return 1;
  }
  poll(NULL,0,5);
 }
 lua_pushboolean(L,0);return 1;
}
static int adapter_ready(lua_State *L) {
 struct pollfd p={0,POLLIN,0};int rc=poll(&p,1,80);
 lua_pushboolean(L,rc>0 && (p.revents&(POLLIN|POLLHUP)));return 1;
}
int luaopen_homepublish_controller_test(lua_State *L) {
 if(prctl(PR_SET_CHILD_SUBREAPER,1))return luaL_error(L,"subreaper unavailable");
 static const luaL_Reg functions[]={{"start",adapter_start},{"renew",adapter_renew},{"stop",adapter_stop},{"ready",adapter_ready},{NULL,NULL}};
 luaL_register(L,"homepublish_controller_test",functions);return 1;
}
