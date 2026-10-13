/* Fault injection only, linked into a separate test binary, never installed. */
#define _GNU_SOURCE
#undef fork
#undef mkdirat
#include <unistd.h>
#include <errno.h>
#include <stdlib.h>
#include <sys/stat.h>
pid_t test_fork(void) {
 static int first=1;
 if(first && getenv("HOMEPUBLISH_PREFORK_DELAY")) {first=0;sleep(5);}
 return fork();
}
int test_mkdirat(int dir,const char *name,mode_t mode) {
 int rc=mkdirat(dir,name,mode);
 if(rc==0 && getenv("HOMEPUBLISH_LOCK_DELAY")) sleep(5);
 return rc;
}
int test_fsync(int fd) {
 (void)fd;
 if(getenv("HOMEPUBLISH_DELAY")) sleep(5);
 errno=EIO;
 return -1;
}
