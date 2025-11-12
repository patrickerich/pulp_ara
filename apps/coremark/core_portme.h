/*
CoreMark port layer for Ara apps environment (bare-metal, no OS).
Maps timing to rdcycle() and uses static memory.
*/

#ifndef CORE_PORTME_H
#define CORE_PORTME_H

#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include "encoding.h"  // rdcycle()
#ifndef HAS_STDIO
#define HAS_STDIO 1
#endif

/* Basic CoreMark typedefs */
typedef signed short   ee_s16;
typedef unsigned short ee_u16;
typedef signed int     ee_s32;
typedef double         ee_f32;
typedef unsigned char  ee_u8;
typedef unsigned int   ee_u32;
typedef unsigned long  ee_u64;

typedef size_t         ee_size_t;

/* Pointer-sized integer and tick type */
typedef ee_u64         ee_ptr_int;
typedef ee_ptr_int     CORE_TICKS;

/* Configuration: single-thread, static memory, volatile seeds, printf enabled */
#ifndef MULTITHREAD
#define MULTITHREAD 1
#endif

#ifndef MEM_METHOD
#define MEM_METHOD 0 /* MEM_STATIC */
#endif

#ifndef SEED_METHOD
#define SEED_METHOD 2 /* SEED_VOLATILE */
#endif

#ifndef HAS_PRINTF
#define HAS_PRINTF 1
#endif

/* Compiler/version strings for reporting; best-effort defaults */
#ifndef COMPILER_VERSION
#define COMPILER_VERSION "LLVM/Clang"
#endif

#ifndef COMPILER_FLAGS
#define COMPILER_FLAGS "-O3 -static -ffast-math"
#endif

#ifndef MEM_LOCATION
#define MEM_LOCATION ""
#endif

#ifndef SC_MEM_LOCATION
#define SC_MEM_LOCATION "UNSPECIFIED(" MEM_LOCATION ") RATIOS:1"
#endif

/* 4-byte alignment helper (same as CVA6 port) */
#define align_mem(x) (void *)(4 + (((ee_ptr_int)(x)-1) & ~3))

/* CoreMark time base helpers */
#define CORETIMETYPE ee_u64

/* Expose default context count symbol */
extern ee_u32 default_num_contexts;

/* Portability hooks */
typedef struct CORE_PORTABLE_S
{
    ee_u8 portable_id;
} core_portable;

void portable_init(core_portable *p, int *argc, char *argv[]);
void portable_fini(core_portable *p);

/* Timing hooks implemented with rdcycle() */
static inline ee_u64 core_rdcycle(void) { return (ee_u64)rdcycle(); }

#endif /* CORE_PORTME_H */