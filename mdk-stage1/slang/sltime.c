/* time related system calls */
/* Copyright (c) 1992, 1999, 2001 John E. Davis
 * This file is part of the S-Lang library.
 *
 * You may distribute under the terms of either the GNU General Public
 * License or the Perl Artistic License.
 */

#include "slinclud.h"

#include <sys/types.h>
#include <time.h>

#if defined(__BORLANDC__)
# include <dos.h>
#endif
#if defined(__GO32__) || defined(__WATCOMC__)
# include <dos.h>
# include <bios.h>
#endif

#include <errno.h>

#include "slang.h"
#include "_slang.h"

#ifdef __WIN32__
#include <windows.h>
/* Sleep is defined badly in MSVC... */
# ifdef _MSC_VER
#  define sleep(n) _sleep((n)*1000)
# else
#  ifdef sleep
#   undef sleep
#  endif
#  define sleep(x) if(x)Sleep((x)*1000)
# endif
#endif


#if defined(IBMPC_SYSTEM)
/* For other system (Unix and VMS), _SLusleep is in sldisply.c */
int _SLusleep (unsigned long s)
{
   sleep (s/1000000L);
   s = s % 1000000L;

# if defined(__WIN32__)
   Sleep (s/1000);
#else
# if defined(__IBMC__)
   DosSleep(s/1000);
# else
#  if defined(_MSC_VER)
   _sleep (s/1000);
#  endif
# endif
#endif
   return 0;
}
#endif

#if defined(__IBMC__) && !defined(_AIX)
/* sleep is not a standard function in VA3. */
unsigned int sleep (unsigned int seconds)
{
   DosSleep(1000L * ((long)seconds));
   return 0;
}
#endif

static char *ctime_cmd (unsigned long *tt)
{
   char *t;

   t = ctime ((time_t *) tt);
   t[24] = 0;  /* knock off \n */
   return (t);
}

static void sleep_cmd (void)
{
   unsigned int secs;
#if SLANG_HAS_FLOAT
   unsigned long usecs;
   double x;

   if (-1 == SLang_pop_double (&x, NULL, NULL))
     return;

   if (x < 0.0) 
     x = 0.0;
   secs = (unsigned int) x;
   sleep (secs);
   x -= (double) secs;
   usecs = (unsigned long) (1e6 * x);
   if (usecs > 0) _SLusleep (usecs);
#else
   if (-1 == SLang_pop_uinteger (&secs))
     return;
   if (secs != 0) sleep (secs);
#endif
}

static unsigned long _time_cmd (void)
{
   return (unsigned long) time (NULL);
}

#if defined(__GO32__)
static char *djgpp_current_time (void) /*{{{*/
{
   union REGS rg;
   unsigned int year;
   unsigned char month, day, weekday, hour, minute, sec;
   char days[] = "SunMonTueWedThuFriSat";
   char months[] = "JanFebMarAprMayJunJulAugSepOctNovDec";
   static char the_date[26];

   rg.h.ah = 0x2A;
#ifndef __WATCOMC__
   int86(0x21, &rg, &rg);
   year = rg.x.cx & 0xFFFF;
#else
   int386(0x21, &rg, &rg);
   year = rg.x.ecx & 0xFFFF;
#endif

   month = 3 * (rg.h.dh - 1);
   day = rg.h.dl;
   weekday = 3 * rg.h.al;

   rg.h.ah = 0x2C;

#ifndef __WATCOMC__
   int86(0x21, &rg, &rg);
#else
   int386(0x21, &rg, &rg);
#endif

   hour = rg.h.ch;
   minute = rg.h.cl;
   sec = rg.h.dh;

   /* we want this form: Thu Apr 14 15:43:39 1994\n  */
   sprintf(the_date, "%.3s %.3s%3d %02d:%02d:%02d %d\n",
	   days + weekday, months + month,
	   day, hour, minute, sec, year);
   return the_date;
}

/*}}}*/

#endif

char *SLcurrent_time_string (void) /*{{{*/
{
   char *the_time;
#ifndef __GO32__
   time_t myclock;

   myclock = time((time_t *) 0);
   the_time = (char *) ctime(&myclock);
#else
   the_time = djgpp_current_time ();
#endif
   /* returns the form Sun Sep 16 01:03:52 1985\n\0 */
   the_time[24] = '\0';
   return(the_time);
}

/*}}}*/

static int push_tm_struct (struct tm *tms)
{
   char *field_names [9];
   unsigned char field_types[9];
   VOID_STAR field_values [9];
   int int_values [9];
   unsigned int i;

   if (tms == NULL)
     return SLang_push_null ();

   field_names [0] = "tm_sec"; int_values [0] = tms->tm_sec;
   field_names [1] = "tm_min"; int_values [1] = tms->tm_min;
   field_names [2] = "tm_hour"; int_values [2] = tms->tm_hour;
   field_names [3] = "tm_mday"; int_values [3] = tms->tm_mday;
   field_names [4] = "tm_mon"; int_values [4] = tms->tm_mon;
   field_names [5] = "tm_year"; int_values [5] = tms->tm_year;
   field_names [6] = "tm_wday"; int_values [6] = tms->tm_wday;
   field_names [7] = "tm_yday"; int_values [7] = tms->tm_yday;
   field_names [8] = "tm_isdst"; int_values [8] = tms->tm_isdst;

   for (i = 0; i < 9; i++)
     {
	field_types [i] = SLANG_INT_TYPE;
	field_values [i] = (VOID_STAR) (int_values + i);
     }

   return SLstruct_create_struct (9, field_names, field_types, field_values);
}


static void localtime_cmd (long *t)
{
   time_t tt = (time_t) *t;
   (void) push_tm_struct (localtime (&tt));
}
   
static void gmtime_cmd (long *t)
{
#ifdef HAVE_GMTIME
   time_t tt = (time_t) *t;
   (void) push_tm_struct (gmtime (&tt));
#else
   localtime_cmd (t);
#endif
}

#ifdef HAVE_TIMES

# ifdef HAVE_SYS_TIMES_H
#  include <sys/times.h>
# endif

#include <limits.h>

#ifdef CLK_TCK
# define SECS_PER_TICK (1.0/(double)CLK_TCK)
#else 
# ifdef CLOCKS_PER_SEC
#  define SECS_PER_TICK (1.0/(double)CLOCKS_PER_SEC)
# else
#  define SECS_PER_TICK (1.0/60.0)
# endif
#endif

static void times_cmd (void)
{
   double dvals[4];
   struct tms t;
   VOID_STAR field_values[4];
   char *field_names[4];
   unsigned int i;
   unsigned char field_types[4];
   
   (void) times (&t);

   field_names[0] = "tms_utime";   dvals[0] = (double)t.tms_utime; 
   field_names[1] = "tms_stime";   dvals[1] = (double)t.tms_stime; 
   field_names[2] = "tms_cutime";  dvals[2] = (double)t.tms_cutime;
   field_names[3] = "tms_cstime";  dvals[3] = (double)t.tms_cstime;

   for (i = 0; i < 4; i++)
     {
	dvals[i] *= SECS_PER_TICK;
	field_values[i] = (VOID_STAR) &dvals[i];
	field_types[i] = SLANG_DOUBLE_TYPE;
     }
   (void) SLstruct_create_struct (4, field_names, field_types, field_values);
}

static struct tms Tic_TMS;

static void tic_cmd (void)
{
   (void) times (&Tic_TMS);
}

static double toc_cmd (void)
{
   struct tms t;
   double d;

   (void) times (&t);
   d = ((t.tms_utime - Tic_TMS.tms_utime)
	+ (t.tms_stime - Tic_TMS.tms_stime)) * SECS_PER_TICK;
   Tic_TMS = t;
   return d;
}

#endif				       /* HAVE_TIMES */


static SLang_Intrin_Fun_Type Time_Funs_Table [] =
{
   MAKE_INTRINSIC_1("ctime", ctime_cmd, SLANG_STRING_TYPE, SLANG_ULONG_TYPE),
   MAKE_INTRINSIC_0("sleep", sleep_cmd, SLANG_VOID_TYPE),
   MAKE_INTRINSIC_0("_time", _time_cmd, SLANG_ULONG_TYPE),
   MAKE_INTRINSIC_0("time", SLcurrent_time_string, SLANG_STRING_TYPE),
   MAKE_INTRINSIC_1("localtime", localtime_cmd, SLANG_VOID_TYPE, SLANG_LONG_TYPE),
   MAKE_INTRINSIC_1("gmtime", gmtime_cmd, SLANG_VOID_TYPE, SLANG_LONG_TYPE),

#ifdef HAVE_TIMES
   MAKE_INTRINSIC_0("times", times_cmd, SLANG_VOID_TYPE),
   MAKE_INTRINSIC_0("tic", tic_cmd, SLANG_VOID_TYPE),
   MAKE_INTRINSIC_0("toc", toc_cmd, SLANG_DOUBLE_TYPE),
#endif
   SLANG_END_INTRIN_FUN_TABLE
};

int _SLang_init_sltime (void)
{
#ifdef HAVE_TIMES
   (void) tic_cmd ();
#endif
   return SLadd_intrin_fun_table (Time_Funs_Table, NULL);
}

