/* Pathname intrinsic functions */
/* Copyright (c) 1999, 2001 John E. Davis
 * This file is part of the S-Lang library.
 *
 * You may distribute under the terms of either the GNU General Public
 * License or the Perl Artistic License.
 */

#include "slinclud.h"

#include "slang.h"
#include "_slang.h"

static void path_concat (char *a, char *b)
{
   SLang_push_malloced_string (SLpath_dircat (a,b));
}

static void path_extname (char *path)
{
#ifdef VMS
   char *p;
#endif

   path = SLpath_extname (path);
#ifndef VMS
   SLang_push_string (path);
#else
   p = strchr (path, ';');
   if (p == NULL)
     (void)SLang_push_string (p);
   else
     (void)SLang_push_malloced_string (SLmake_nstring (path, (unsigned int)(p - path)));
#endif
}

static void path_basename (char *path)
{
   (void) SLang_push_string (SLpath_basename (path));
}

static void path_dirname (char *path)
{
   (void) SLang_push_malloced_string (SLpath_dirname (path));
}

static void path_sans_extname (char *path)
{
   (void) SLang_push_malloced_string (SLpath_pathname_sans_extname (path));
}



static SLang_Intrin_Fun_Type Path_Name_Table [] =
{
   MAKE_INTRINSIC_SS("path_concat", path_concat, SLANG_VOID_TYPE),
   MAKE_INTRINSIC_S("path_extname", path_extname, SLANG_VOID_TYPE),
   MAKE_INTRINSIC_S("path_dirname", path_dirname, SLANG_VOID_TYPE),
   MAKE_INTRINSIC_S("path_basename", path_basename, SLANG_VOID_TYPE),
   MAKE_INTRINSIC_S("path_sans_extname", path_sans_extname, SLANG_VOID_TYPE),
   MAKE_INTRINSIC_S("path_is_absolute", SLpath_is_absolute_path, SLANG_INT_TYPE),
   SLANG_END_INTRIN_FUN_TABLE
};

int SLang_init_ospath (void)
{
   if (-1 == SLadd_intrin_fun_table(Path_Name_Table, "__OSPATH__"))
     return -1;
   
   return 0;
}


