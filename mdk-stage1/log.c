/*
 * Guillaume Cottenceau (gc@mandrakesoft.com)
 *
 * Copyright 2000 MandrakeSoft
 *
 * This software may be freely redistributed under the terms of the GNU
 * public license.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 *
 */

/*
 * Portions from Erik Troan (ewt@redhat.com)
 *
 * Copyright 1996 Red Hat Software 
 *
 */


#include <fcntl.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

#include "log.h"

static FILE * logfile = NULL;


void do_log_message(const char * s, va_list args)
{
	if (!logfile) return;
	
	fprintf(logfile, "* ");
	vfprintf(logfile, s, args);
	fprintf(logfile, "\n");
	
	fflush(logfile);
}


void log_message(const char * s, ...)
{
	va_list args;
	
	va_start(args, s);
	do_log_message(s, args);
	va_end(args);
	
	return;
}


void open_log(int testing)
{
    if (!testing)
    {
	    logfile = fopen("/dev/tty3", "w");
	    if (!logfile)
		    logfile = fopen("/tmp/install.log", "a");
    }
    else
	    logfile = fopen("debug.log", "w");
}

void close_log(void)
{
	if (logfile)
		fclose(logfile);
}
