/* Copyright (c) 1998, 1999, 2001 John E. Davis
 * This file is part of the S-Lang library.
 *
 * You may distribute under the terms of either the GNU General Public
 * License or the Perl Artistic License.
 */
#include "slinclud.h"

#include "slang.h"
#include "_slang.h"

int SLang_init_all (void)
{
   if ((-1 == SLang_init_slang ())
       || (-1 == SLang_init_slmath ())
       || (-1 == SLang_init_posix_dir ())
       || (-1 == SLang_init_posix_process ())
       || (-1 == SLang_init_stdio ())
       || (-1 == SLang_init_array ())
       || (-1 == SLang_init_posix_io ())
       || (-1 == SLang_init_ospath ())
       )
     return -1;

   return 0;
}

