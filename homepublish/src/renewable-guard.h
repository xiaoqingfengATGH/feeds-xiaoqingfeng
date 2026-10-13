#ifndef HP_RENEWABLE_GUARD_H
#define HP_RENEWABLE_GUARD_H
#include <stdint.h>
#include <sys/types.h>
/* Internal inherited-channel ABI. Never a browser or arbitrary-command API. */
#define HP_WINDOW_MS 600
#define HP_WATCHDOG_MS 200
struct hp_frame { uint64_t generation, epoch, sequence; unsigned char token[16]; uint32_t operation, reserved; };
struct hp_guard { int fd; pid_t pid; uint64_t generation, epoch, sequence; unsigned char token[16]; };
#ifdef HP_GUARD_TEST
int hp_guard_start(struct hp_guard *, uint64_t, uint64_t, unsigned, void (*)(int), int);
#endif
int hp_guard_send(struct hp_guard *, uint32_t);
#endif
