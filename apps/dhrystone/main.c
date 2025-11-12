// See LICENSE for license details.

//**************************************************************************
// Dhrystone benchmark (CVA6 variant adapted for Ara apps)
//--------------------------------------------------------------------------
//
// Build: make -C apps bin/dhrystone
// Run on RTL: trace=1 make -C hardware verilate && trace=1 app=dhrystone make -C hardware simv

#include "dhrystone.h"
#ifdef SPIKE
#include "util.h"
#include <stdio.h>
#elif defined ARA_LINUX
#include <stdio.h>
#else
#include "printf.h"
#endif

// Optional lightweight debug printer; implemented in dhrystone.c (no-op)
void debug_printf(const char* str, ...);

/* Global Variables: */
Rec_Pointer     Ptr_Glob;
Rec_Pointer     Next_Ptr_Glob;
int             Int_Glob;
Boolean         Bool_Glob;
char            Ch_1_Glob;
char            Ch_2_Glob;
int             Arr_1_Glob[50];
int             Arr_2_Glob[50][50];

/* forward declaration necessary since Enumeration may not simply be int */
Enumeration     Func_1 (Capital_Letter Ch_1_Par_Val, Capital_Letter Ch_2_Par_Val);

#ifndef REG
        Boolean Reg = false;
#define REG
        /* REG becomes defined as empty */
        /* i.e. no register variables   */
#else
        Boolean Reg = true;
#undef REG
#define REG register
#endif

Boolean         Done;

long            Begin_Time;
long            End_Time;
long            User_Time;
long            Microseconds;
long            Dhrystones_Per_Second;

/* end of variables for time measurement */

int main (int argc, char** argv)
{
  One_Fifty       Int_1_Loc;
  REG One_Fifty   Int_2_Loc;
  One_Fifty       Int_3_Loc;
  REG char        Ch_Index;
  Enumeration     Enum_Loc;
  Str_30          Str_1_Loc;
  Str_30          Str_2_Loc;
  REG int         Run_Index;
  REG int         Number_Of_Runs;

  /* Arguments */
  Number_Of_Runs = NUMBER_OF_RUNS;

  /* Initializations */
  static Rec_Type Next_Rec_Glob_Storage;
  static Rec_Type Rec_Glob_Storage;
  Next_Ptr_Glob = &Next_Rec_Glob_Storage;
  Ptr_Glob      = &Rec_Glob_Storage;

  Ptr_Glob->Ptr_Comp                    = Next_Ptr_Glob;
  Ptr_Glob->Discr                       = Ident_1;
  Ptr_Glob->variant.var_1.Enum_Comp     = Ident_3;
  Ptr_Glob->variant.var_1.Int_Comp      = 40;
  strcpy (Ptr_Glob->variant.var_1.Str_Comp,
          "DHRYSTONE PROGRAM, SOME STRING");
  strcpy (Str_1_Loc, "DHRYSTONE PROGRAM, 1'ST STRING");

  Arr_2_Glob[8][7] = 10;
        /* Was missing in published program. Without this statement,    */
        /* Arr_2_Glob [8][7] would have an undefined value.             */
        /* Warning: With 16-Bit processors and Number_Of_Runs > 32000,  */
        /* overflow may occur for this array element.                   */

  debug_printf("\n");
  debug_printf("Dhrystone Benchmark, Version %s\n", Version);
  if (Reg)
    debug_printf("Program compiled with 'register' attribute\n");
  else
    debug_printf("Program compiled without 'register' attribute\n");
  debug_printf("Using %s, HZ=%d\n", CLOCK_TYPE, HZ);
  debug_printf("\n");

  Done = false;
  while (!Done) {
    debug_printf("Trying %d runs through Dhrystone:\n", Number_Of_Runs);

    /* Start timer */
    setStats(1);
    Start_Timer();

    for (Run_Index = 1; Run_Index <= Number_Of_Runs; ++Run_Index)
    {
      Proc_5();
      Proc_4();
      /* Ch_1_Glob == 'A', Ch_2_Glob == 'B', Bool_Glob == true */
      Int_1_Loc = 2;
      Int_2_Loc = 3;
      strcpy (Str_2_Loc, "DHRYSTONE PROGRAM, 2'ND STRING");
      Enum_Loc = Ident_2;
      Bool_Glob = ! Func_2 (Str_1_Loc, Str_2_Loc);
      /* Bool_Glob == 1 */
      while (Int_1_Loc < Int_2_Loc)  /* loop body executed once */
      {
        Int_3_Loc = 5 * Int_1_Loc - Int_2_Loc;
        /* Int_3_Loc == 7 */
        Proc_7 (Int_1_Loc, Int_2_Loc, &Int_3_Loc);
        /* Int_3_Loc == 7 */
        Int_1_Loc += 1;
      } /* while */
      /* Int_1_Loc == 3, Int_2_Loc == 3, Int_3_Loc == 7 */
      Proc_8 (Arr_1_Glob, Arr_2_Glob, Int_1_Loc, Int_3_Loc);
      /* Int_Glob == 5 */
      Proc_1 (Ptr_Glob);
      for (Ch_Index = 'A'; Ch_Index <= Ch_2_Glob; ++Ch_Index)
      { /* loop body executed twice */
        if (Enum_Loc == Func_1 (Ch_Index, 'C'))
        { /* then, not executed */
          Proc_6 (Ident_1, &Enum_Loc);
          strcpy (Str_2_Loc, "DHRYSTONE PROGRAM, 3'RD STRING");
          Int_2_Loc = Run_Index;
          Int_Glob = Run_Index;
        }
      }
      /* Int_1_Loc == 3, Int_2_Loc == 3, Int_3_Loc == 7 */
      Int_2_Loc = Int_2_Loc * Int_1_Loc;
      Int_1_Loc = Int_2_Loc / Int_3_Loc;
      Int_2_Loc = 7 * (Int_2_Loc - Int_3_Loc) - Int_1_Loc;
      /* Int_1_Loc == 1, Int_2_Loc == 13, Int_3_Loc == 7 */
      Proc_2 (&Int_1_Loc);
      /* Int_1_Loc == 5 */
    } /* loop "for Run_Index" */

    /* Stop timer */
    Stop_Timer();
    setStats(0);

    User_Time = End_Time - Begin_Time;

    if (User_Time < Too_Small_Time)
    {
      printf("Measured time too small to obtain meaningful results\n");
      Number_Of_Runs = Number_Of_Runs * 10;
      printf("\n");
    } else Done = true;
  }

  debug_printf("Final values of the variables used in the benchmark:\n");
  debug_printf("\n");
  debug_printf("Int_Glob:            %d\n", Int_Glob);
  debug_printf("        should be:   %d\n", 5);
  debug_printf("Bool_Glob:           %d\n", Bool_Glob);
  debug_printf("        should be:   %d\n", 1);
  debug_printf("Ch_1_Glob:           %c\n", Ch_1_Glob);
  debug_printf("        should be:   %c\n", 'A');
  debug_printf("Ch_2_Glob:           %c\n", Ch_2_Glob);
  debug_printf("        should be:   %c\n", 'B');
  debug_printf("Arr_1_Glob[8]:       %d\n", Arr_1_Glob[8]);
  debug_printf("        should be:   %d\n", 7);
  debug_printf("Arr_2_Glob[8][7]:    %d\n", Arr_2_Glob[8][7]);
  debug_printf("        should be:   Number_Of_Runs + 10\n");
  debug_printf("Ptr_Glob->\n");
  debug_printf("  Ptr_Comp:          %ld\n", (long) (Ptr_Glob->Ptr_Comp != 0));
  debug_printf("  Discr:             %d\n", Ptr_Glob->Discr);
  debug_printf("  Enum_Comp:         %d\n", Ptr_Glob->variant.var_1.Enum_Comp);
  debug_printf("  Int_Comp:          %d\n", Ptr_Glob->variant.var_1.Int_Comp);
  debug_printf("  Str_Comp:          %s\n", Ptr_Glob->variant.var_1.Str_Comp);
  debug_printf("Next_Ptr_Glob->\n");
  debug_printf("  Ptr_Comp:          %ld\n", (long) (Next_Ptr_Glob->Ptr_Comp != 0));
  debug_printf("  Discr:             %d\n", Next_Ptr_Glob->Discr);
  debug_printf("  Enum_Comp:         %d\n", Next_Ptr_Glob->variant.var_1.Enum_Comp);
  debug_printf("  Int_Comp:          %d\n", Next_Ptr_Glob->variant.var_1.Int_Comp);
  debug_printf("  Str_Comp:          %s\n", Next_Ptr_Glob->variant.var_1.Str_Comp);
  debug_printf("\n");

  Microseconds = ((User_Time / Number_Of_Runs) * Mic_secs_Per_Second) / HZ;
  Dhrystones_Per_Second = (HZ * Number_Of_Runs) / User_Time;

  printf("Microseconds for one run through Dhrystone: %ld\n", Microseconds);
  printf("Dhrystones per Second:                      %ld\n", Dhrystones_Per_Second);

  return 0;
}

void Proc_1 (Rec_Pointer Ptr_Val_Par)
{
  REG Rec_Pointer Next_Record = Ptr_Val_Par->Ptr_Comp;

  structassign (*Ptr_Val_Par->Ptr_Comp, *Ptr_Glob);
  Ptr_Val_Par->variant.var_1.Int_Comp = 5;
  Next_Record->variant.var_1.Int_Comp = Ptr_Val_Par->variant.var_1.Int_Comp;
  Next_Record->Ptr_Comp = Ptr_Val_Par->Ptr_Comp;
  Proc_3 (&Next_Record->Ptr_Comp);
  if (Next_Record->Discr == Ident_1)
  {
    Next_Record->variant.var_1.Int_Comp = 6;
    Proc_6 (Ptr_Val_Par->variant.var_1.Enum_Comp,
            &Next_Record->variant.var_1.Enum_Comp);
    Next_Record->Ptr_Comp = Ptr_Glob->Ptr_Comp;
    Proc_7 (Next_Record->variant.var_1.Int_Comp, 10,
            &Next_Record->variant.var_1.Int_Comp);
  }
  else
    structassign (*Ptr_Val_Par, *Ptr_Val_Par->Ptr_Comp);
}

void Proc_2 (One_Fifty *Int_Par_Ref)
{
  One_Fifty  Int_Loc;
  Enumeration   Enum_Loc;

  Int_Loc = *Int_Par_Ref + 10;
  do
    if (Ch_1_Glob == 'A')
    {
      Int_Loc -= 1;
      *Int_Par_Ref = Int_Loc - Int_Glob;
      Enum_Loc = Ident_1;
    }
  while (Enum_Loc != Ident_1);
}

void Proc_3 (Rec_Pointer *Ptr_Ref_Par)
{
  if (Ptr_Glob != Null)
    *Ptr_Ref_Par = Ptr_Glob->Ptr_Comp;
  Proc_7 (10, Int_Glob, &Ptr_Glob->variant.var_1.Int_Comp);
}

void Proc_4 (void)
{
  Boolean Bool_Loc;

  Bool_Loc = Ch_1_Glob == 'A';
  Bool_Glob = Bool_Loc | Bool_Glob;
  Ch_2_Glob = 'B';
}

void Proc_5 (void)
{
  Ch_1_Glob = 'A';
  Bool_Glob = false;
}