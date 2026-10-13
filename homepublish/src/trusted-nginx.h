/* Internal server-owned profile. No executable/library/environment parameters.
 * Production is deliberately unavailable until an installation authority exists. */
#ifndef HP_TRUSTED_NGINX_H
#define HP_TRUSTED_NGINX_H
#include "owned-runtime.h"
int hp_trusted_nginx_verify(void);
int hp_trusted_nginx_exec(struct hp_owned_runtime *, const char *trusted_prefix);
#endif
