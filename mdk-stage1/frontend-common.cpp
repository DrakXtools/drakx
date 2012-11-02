/*
 * Guillaume Cottenceau (gc@mandriva.com)
 *
 * Copyright 2000 Mandriva
 *
 * This software may be freely redistributed under the terms of the GNU
 * public license.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 *
 */

#include <stdlib.h>
#include <stdarg.h>
#include <string.h>

#include <probing.h>

#include "frontend.h"

const char * binary_name = NULL;

void info_message(const char *msg, ...)
{
	va_list args;
	va_start(args, msg);
	vinfo_message(msg, args);
	va_end(args);
}

void wait_message(const char *msg, ...)
{
	va_list args;
	va_start(args, msg);
	vwait_message(msg, args);
	va_end(args);
}

void error_message(const char *msg, ...)
{
	va_list args;
	va_start(args, msg);
	verror_message(msg, args);
	va_end(args);
}

enum return_type ask_from_list_comments(const char *msg, const char ** elems, const char ** elems_comments, char ** choice)
{
	int answer = 0;
	enum return_type results;

	results = ask_from_list_index(msg, elems, elems_comments, &answer);

	if (results == RETURN_OK)
		*choice = strdup(elems[answer]);

	return results;
}

enum return_type ask_from_list(const char *msg, const char ** elems, char ** choice)
{
	return ask_from_list_comments(msg, elems, NULL, choice);
}
