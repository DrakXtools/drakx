/*
 * Guillaume Cottenceau (gc@mandrakesoft.com)
 *
 * Copyright 2000 Mandrakesoft
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

#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <stdarg.h>
#include <stdio.h>
#include <string.h>
#include <time.h>
#include <errno.h>
#include "stage1.h"

#include "log.h"

static FILE * logtty  = NULL;
static FILE * logfile = NULL;


void vlog_message(const char * s, va_list args)
{
	va_list args_copy;
	va_copy(args_copy, args);

	if (logfile) {
		fprintf(logfile, "* ");
		vfprintf(logfile, s, args);
		fprintf(logfile, "\n");
		fflush(logfile);
	}
	if (logtty) {
		fprintf(logtty, "* ");
		vfprintf(logtty, s, args_copy);
		fprintf(logtty, "\n");
		fflush(logtty);
	}

	va_end(args_copy);
}


void log_message(const char * s, ...)
{
	va_list args;
	va_start(args, s);
	vlog_message(s, args);
	va_end(args);
	
	return;
}

void log_perror(const char *msg)
{
	log_message("%s: %s", msg, strerror(errno));
}


void open_log(void)
{
	if (!IS_TESTING) {
		logtty  = fopen("/dev/tty3", "w");
		logfile = fopen("/tmp/stage1.log", "w");
	}
	else
		logfile = fopen("debug.log", "w");
}

void close_log(void)
{
	if (logfile) {
		log_message("stage1: disconnecting life support systems");
		fclose(logfile);
		if (logtty)
			fclose(logtty);
	}
}
