/* Native internal ownership API; never a CLI/wire schema or provider authority. */
#ifndef HP_OWNED_RUNTIME_H
#define HP_OWNED_RUNTIME_H
#include <stddef.h>
struct hp_owned_runtime;
/* parentfd must be independently trusted; fixed child name runtime only. */
struct hp_owned_runtime *hp_owned_prepare(int parentfd);
int hp_owned_file(struct hp_owned_runtime *, unsigned slot, const void *, size_t);
int hp_owned_cleanup(struct hp_owned_runtime *); /* 0 clean, 1 explicit residual */
int hp_owned_dirfd(struct hp_owned_runtime *);
void hp_owned_release(struct hp_owned_runtime *);
#ifdef HP_GUARD_TEST
void hp_guard_bind_owned_test(struct hp_owned_runtime *);
#endif
#endif
