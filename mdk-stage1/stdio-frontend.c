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


/*
 * Each different frontend must implement all functions defined in frontend.h
 */


#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <stdio.h>
#include <stdarg.h>
#include <fcntl.h>
#include "stage1.h"
#include "log.h"
#include "newt.h"

#include "frontend.h"


void init_frontend(void)
{
	printf("Welcome to Linux-Mandrake (" VERSION ") " __DATE__ " " __TIME__ "\n");
}


void finish_frontend(void)
{
}

static void get_any_response(void)
{
	unsigned char t;
	fflush(stdout);
	read(0, &t, 1);
	fcntl(0, F_SETFL, O_NONBLOCK);
	while (read(0, &t, 1) > 0);
	fcntl(0, F_SETFL, 0);
}
	
static int get_int_response(void)
{
	int i = 0; /* (0) tied to Cancel */
	fflush(stdout);
	scanf(" %d", &i);
	return i;
}

static void blocking_msg(char *type, char *fmt, va_list args)
{
	printf(type);
	vprintf(fmt, args);
	get_any_response();
	printf("\n");
}

void error_message(char *msg, ...)
{
	va_list args;
	va_start(args, msg);
	va_end(args);
	blocking_msg("> Error! ", msg, args);
}

void info_message(char *msg, ...)
{
	va_list args;
	va_start(args, msg);
	va_end(args);
	blocking_msg("> Info! ", msg, args);
}

void wait_message(char *msg, ...)
{
	va_list args;
	printf("Please wait: ");
	va_start(args, msg);
	vprintf(msg, args);
	va_end(args);
	fflush(stdout);
}

void remove_wait_message(void)
{
	printf("\n");
}


enum return_type ask_from_list_comments(char *msg, char ** elems, char ** elems_comments, char ** choice)
{
	char ** sav_elems = elems;
	int i, j;

	printf("> %s\n(0) Cancel\n", msg);
	i = 1;
	while (elems && *elems) {
		printf("(%d) %s (%s)\n", i, *elems, *elems_comments);
		i++;
		elems++;
		elems_comments++;
	}

	printf("? ");

	j = get_int_response();

	if (j == 0)
		return RETURN_BACK;

	if (j >= 1 && j < i) {
		*choice = strdup(sav_elems[j-1]);
		return RETURN_OK;
	}

	return RETURN_ERROR;
}


enum return_type ask_from_list(char *msg, char ** elems, char ** choice)
{
	char ** sav_elems = elems;
	int i, j;

	printf("> %s\n(0) Cancel\n", msg);
	i = 1;
	while (elems && *elems) {
		printf("(%d) %s\n", i, *elems);
		i++;
		elems++;
	}

	printf("? "); 

	j = get_int_response();

	if (j == 0)
		return RETURN_BACK;

	if (j >= 1 && j < i) {
		*choice = strdup(sav_elems[j-1]);
		return RETURN_OK;
	}

	return RETURN_ERROR;
}


enum return_type ask_yes_no(char *msg)
{
	int j;

	printf("> %s\n(0) Yes\n(1) No\n(2) Back\n? ", msg);

	j = get_int_response();

	if (j == 0)
		return RETURN_OK;
	else if (j == 2)
		return RETURN_BACK;
	else return RETURN_ERROR;
}
