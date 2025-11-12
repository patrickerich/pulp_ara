/*
CoreMark port layer for Ara apps environment (bare-metal, no OS).
Implements timing via rdcycle() and uses static memory by default.
*/

#include "coremark.h"
#include "encoding.h"  // rdcycle()

/* Number of contexts (threads) to run */
ee_u32 default_num_contexts = 1;

/* Timing */
static ee_u64 start_cycles = 0;
static ee_u64 stop_cycles  = 0;

void portable_init(core_portable *p, int *argc, char *argv[]) {
  (void)argc; (void)argv;
  if (p) p->portable_id = 1;
}

void portable_fini(core_portable *p) {
  if (p) p->portable_id = 0;
}

void start_time(void) {
  start_cycles = (ee_u64)rdcycle();
}

void stop_time(void) {
  stop_cycles = (ee_u64)rdcycle();
}

CORE_TICKS get_time(void) {
  /* Return elapsed cycles */
  return (CORE_TICKS)(stop_cycles - start_cycles);
}

secs_ret time_in_secs(CORE_TICKS ticks) {
  /* Assume 1 MHz for reporting, consistent with CVA6 port */
  return (secs_ret)(ticks / 1000000u);
}

/* SEEDS: choose "performance run" defaults when using volatile seeds */
#if (SEED_METHOD == SEED_VOLATILE)
volatile ee_s32 seed1_volatile = 0x0;
volatile ee_s32 seed2_volatile = 0x0;
volatile ee_s32 seed3_volatile = 0x66;
#ifndef ITERATIONS
#define ITERATIONS 0
#endif
volatile ee_s32 seed4_volatile = ITERATIONS;
volatile ee_s32 seed5_volatile = 0;
#endif

/* Optional heap hooks (unused with MEM_STATIC, provided for link completeness) */
void * portable_malloc(ee_size_t size) {
#if (MEM_METHOD == MEM_MALLOC)
  extern void* malloc(ee_size_t);
  return malloc(size);
#else
  (void)size;
  return (void*)0;
#endif
}

void portable_free(void *p) {
#if (MEM_METHOD == MEM_MALLOC)
  extern void free(void*);
  free(p);
#else
  (void)p;
#endif
}