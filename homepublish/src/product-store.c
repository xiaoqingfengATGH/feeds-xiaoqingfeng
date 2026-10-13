/* SPDX-License-Identifier: Apache-2.0 */
#define _GNU_SOURCE
#include <lua.h>
#include <lauxlib.h>
#include <sys/stat.h>
#include <sys/file.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <stdlib.h>
#include <string.h>
#ifndef PRODUCT_ROOT
#define PRODUCT_ROOT "/etc/homepublish/product"
#endif
#define LIMIT 262144
static int private_file(int fd) {
 struct stat st;
 return fd>=0 && fstat(fd,&st)==0 && S_ISREG(st.st_mode) && st.st_uid==geteuid() && (st.st_mode&0777)==0600 && st.st_nlink==1;
}
static int transaction(lua_State *L) {
 int dir=-1,lock=-1,in=-1,out=-1,failed=0,renamed=0,owned_candidate=0;
 char *buf=NULL; const char *failure="store failure";
 luaL_checktype(L,1,LUA_TFUNCTION);
 if (mkdir(PRODUCT_ROOT,0700)<0 && errno!=EEXIST) goto fail;
 dir=open(PRODUCT_ROOT,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC);
 struct stat st;
 if(dir<0 || fstat(dir,&st)<0 || st.st_uid!=geteuid() || (st.st_mode&0777)!=0700) { failure="unsafe store directory";goto fail; }
 lock=openat(dir,"lock",O_RDWR|O_CREAT|O_NOFOLLOW|O_CLOEXEC,0600);
 if(!private_file(lock)) {failure="unsafe store lock";goto fail;}
 if(flock(lock,LOCK_EX|LOCK_NB)<0) {failure="store busy";goto fail;}
 in=openat(dir,"state",O_RDONLY|O_NOFOLLOW|O_NONBLOCK|O_CLOEXEC);
 if(in<0 && errno!=ENOENT) {failure="unsafe store state";goto fail;}
 lua_pushvalue(L,1);
 if(in>=0) {
  if(!private_file(in) || fstat(in,&st)<0 || st.st_size<=0 || st.st_size>LIMIT) {failure="unsafe store state";goto fail;}
  size_t size=(size_t)st.st_size,used=0;buf=malloc(size);if(!buf) goto fail;
  while(used<size) {ssize_t n=read(in,buf+used,size-used);if(n<0&&errno==EINTR)continue;if(n<=0)goto fail;used+=(size_t)n;}
  lua_pushlstring(L,buf,size);free(buf);buf=NULL;close(in);in=-1;
 } else lua_pushnil(L);
 if(lua_pcall(L,1,2,0)!=0) {failure="invalid stored state or request";goto fail;}
 /* callback returns new bytes (nil means read-only), plus public response. */
 if(!lua_isnil(L,-2)) {
  if(lua_type(L,-2)!=LUA_TSTRING) goto fail;
  size_t size=0;const char *data=lua_tolstring(L,-2,&size);if(size==0||size>LIMIT)goto fail;
  /* A crash may leave a candidate; never unlink symlinks/foreign identities. */
  int old=openat(dir,"candidate",O_RDONLY|O_NOFOLLOW|O_NONBLOCK|O_CLOEXEC);
  if(old>=0) {int safe=private_file(old);close(old);if(!safe) {failure="unsafe store candidate";goto fail;} if(unlinkat(dir,"candidate",0)<0)goto fail;}
  else if(errno!=ENOENT) {failure="unsafe store candidate";goto fail;}
  out=openat(dir,"candidate",O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW|O_CLOEXEC,0600);if(out<0)goto fail;
  owned_candidate=1;
  size_t used=0;while(used<size) {ssize_t n=write(out,data+used,size-used);if(n<0&&errno==EINTR)continue;if(n<=0)goto fail;used+=(size_t)n;}
  if(fsync(out)<0) goto fail;
  /* close may release the descriptor even on EIO/EINTR: never retry it.
   * No candidate may be published before both fsync and close succeed. */
  int closing=out;out=-1;
  if(close(closing)<0) {failure="candidate close failed";goto fail;}
  if(renameat(dir,"candidate",dir,"state")<0)goto fail;
  renamed=1;
  if(fsync(dir)<0) {failure="commit durability unknown; read status";goto fail;}
 }
 goto done;
fail:
 failed=1;
done:
 free(buf);if(in>=0)close(in);
 if(out>=0)close(out);
 if(owned_candidate&&!renamed)unlinkat(dir,"candidate",0);
 if(lock>=0)close(lock);
 if(dir>=0)close(dir);
 if(failed) {lua_pushnil(L);lua_pushstring(L,failure);return 2;}
 return 1;
}
int luaopen_homepublish_store(lua_State *L) {
 static const luaL_Reg functions[]={{"transaction",transaction},{NULL,NULL}};
 luaL_register(L,"homepublish_store",functions);return 1;
}
