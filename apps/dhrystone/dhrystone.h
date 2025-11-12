// See LICENSE for license details.

#ifndef _DHRYSTONE_H
#define _DHRYSTONE_H

/****************** "DHRYSTONE" Benchmark Program ***************************/
#define Version "C, Version 2.2"

/* Compiler and system dependent definitions: */

/* variables for time measurement: */
#include "encoding.h"
#include <stdio.h>
#include <string.h>

#define HZ 1000000
#define Too_Small_Time 1
#define CLOCK_TYPE "rdcycle()"
#define Start_Timer() (Begin_Time = rdcycle())
#define Stop_Timer()  (End_Time = rdcycle())

#define Mic_secs_Per_Second 1000000
#define NUMBER_OF_RUNS 50 /* Default number of runs */

#ifndef setStats
#define setStats(x) ((void)0)
#endif

#ifdef  NOSTRUCTASSIGN
#define structassign(d, s)      memcpy(&(d), &(s), sizeof(d))
#else
#define structassign(d, s)      d = s
#endif

#ifdef  NOENUM
#define Ident_1 0
#define Ident_2 1
#define Ident_3 2
#define Ident_4 3
#define Ident_5 4
  typedef int   Enumeration;
#else
  typedef enum {Ident_1, Ident_2, Ident_3, Ident_4, Ident_5} Enumeration;
#endif
        /* for boolean and enumeration types in Ada, Pascal */

/* General definitions: */

#define Null 0
                /* Value of a Null pointer */
#define true  1
#define false 0

typedef int     One_Thirty;
typedef int     One_Fifty;
typedef char    Capital_Letter;
typedef int     Boolean;
typedef char    Str_30 [31];
typedef int     Arr_1_Dim [50];
typedef int     Arr_2_Dim [50] [50];

typedef struct record
    {
    struct record *Ptr_Comp;
    Enumeration    Discr;
    union {
          struct {
                  Enumeration Enum_Comp;
                  int         Int_Comp;
                  char        Str_Comp [31];
                  } var_1;
          struct {
                  Enumeration E_Comp_2;
                  char        Str_2_Comp [31];
                  } var_2;
          struct {
                  char        Ch_1_Comp;
                  char        Ch_2_Comp;
                  } var_3;
          } variant;
      } Rec_Type, *Rec_Pointer;

/* Extern globals used across translation units */
extern Rec_Pointer Ptr_Glob, Next_Ptr_Glob;
extern int         Int_Glob;
extern Boolean     Bool_Glob;
extern char        Ch_1_Glob, Ch_2_Glob;
extern int         Arr_1_Glob[50];
extern int         Arr_2_Glob[50][50];

/* Dhrystone API */
void        Proc_1 (Rec_Pointer Ptr_Val_Par);
void        Proc_2 (One_Fifty *Int_Par_Ref);
void        Proc_3 (Rec_Pointer *Ptr_Ref_Par);
void        Proc_4 (void);
void        Proc_5 (void);
void        Proc_6 (Enumeration Enum_Val_Par, Enumeration *Enum_Ref_Par);
void        Proc_7 (One_Fifty Int_1_Par_Val, One_Fifty Int_2_Par_Val, One_Fifty *Int_Par_Ref);
void        Proc_8 (Arr_1_Dim Arr_1_Par_Ref, Arr_2_Dim Arr_2_Par_Ref, int Int_1_Par_Val, int Int_2_Par_Val);
Enumeration Func_1 (Capital_Letter Ch_1_Par_Val, Capital_Letter Ch_2_Par_Val);
Boolean     Func_2 (Str_30 Str_1_Par_Ref, Str_30 Str_2_Par_Ref);
Boolean     Func_3 (Enumeration Enum_Par_Val);

#endif