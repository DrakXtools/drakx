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
 * Each different frontend must implement all functions defined in frontend.h
 */


#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <stdio.h>
#include <stdarg.h>
#include <fcntl.h>
#include <sys/ioctl.h>
#include <termios.h>
#include "stage1.h"
#include "log.h"
#include "newt.h"

#include "frontend.h"


void init_frontend(void)
{
	printf("Welcome to " DISTRIB_NAME " (" VERSION ") " __DATE__ " " __TIME__ "\n");
}


void finish_frontend(void)
{
}

static void get_any_response(void)
{
	unsigned char t;
	printf(" (press <enter> to proceed)");
	fflush(stdout);
	read(0, &t, 1);
	fcntl(0, F_SETFL, O_NONBLOCK);
	while (read(0, &t, 1) > 0);
	fcntl(0, F_SETFL, 0);
}
	
static int get_int_response(void)
{
	char s[50];
	int j = 0, i = 0; /* (0) tied to Cancel */
	fflush(stdout);
	read(0, &(s[i++]), 1);
	fcntl(0, F_SETFL, O_NONBLOCK);
	do {
		int v = s[i-1];
		if (v >= '0' && v <= '9')
			j = j*10 + (v - '0');
	} while (read(0, &(s[i++]), 1) > 0 && i < sizeof(s));
	fcntl(0, F_SETFL, 0);
	return j;
}

static char * get_string_response(char * initial_string)
{
	/* I won't use a scanf/%s since I also want the null string to be accepted -- also, I want the initial_string */
	char s[50];
	int i = 0;
	struct termios t;
	
	if (initial_string) {
		printf(initial_string);
		strcpy(s, initial_string);
		i = strlen(s);
	}
	
	/* from ncurses/tinfo/lib_raw.c:(cbreak) */
	tcgetattr(0, &t);
	t.c_lflag &= ~ICANON;
	t.c_lflag |= ISIG;
	t.c_lflag &= ~ECHO;
	t.c_iflag &= ~ICRNL;
	t.c_cc[VMIN] = 1;
	t.c_cc[VTIME] = 0;
	tcsetattr(0, TCSADRAIN, &t);

	fflush(stdout);

	fcntl(0, F_SETFL, O_NONBLOCK);

	while (1) {
		if (read(0, &(s[i]), 1) > 0) {
			if (s[i] == 13)
				break;
			if (s[i] == 127) {
				if (i > 0) {
					printf("\033[D");
					printf(" ");
					printf("\033[D");
					i--;
				}
			} else {
				printf("%c", s[i]);
				i++;
			}
		}
	}

	t.c_lflag |= ICANON;
	t.c_lflag |= ECHO;
	t.c_iflag |= ICRNL; 
	tcsetattr(0, TCSADRAIN, &t);

	fcntl(0, F_SETFL, 0);

	printf("\n");
	s[i] = '\0';
	return strdup(s);
}

static void blocking_msg(char *type, char *fmt, va_list args)
{
	printf(type);
	vprintf(fmt, args);
	get_any_response();
}

void error_message(char *msg, ...)
{
	va_list args;
	va_start(args, msg);
	va_end(args);
	blocking_msg("> Error! ", msg, args);
	unset_param(MODE_AUTOMATIC);
}

void info_message(char *msg, ...)
{
	va_list args;
	va_start(args, msg);
	va_end(args);
	if (!IS_AUTOMATIC)
		blocking_msg("> Notice: ", msg, args);
	else
		vlog_message(msg, args);
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


static int size_progress;
static int actually_drawn;
#define PROGRESS_SIZE 60
void init_progression(char *msg, int size)
{
	int i;
	size_progress = size;
	printf("%s\n", msg);
	if (size) {
		printf("[");
		actually_drawn = 0;
		for (i=0; i<PROGRESS_SIZE; i++)
			printf(".");
		printf("]\033[G[");		/* only works on ANSI-compatibles */
		fflush(stdout);
	}
}

void update_progression(int current_size)
{
	if (size_progress) {
		if (current_size <= size_progress)
			while ((int)((current_size*PROGRESS_SIZE)/size_progress) > actually_drawn) {
				printf("*");
				actually_drawn++;
			}
	} else
		printf("\033[G%d bytes read", current_size);
	
	fflush(stdout);
}

void end_progression(void)
{
	if (size_progress) {
		update_progression(size_progress);
		printf("]\n");
	} else
		printf(" done.\n");
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

	i = 0;
	while (elems && *elems) {
		i++;
		elems++;
	}

	if (i < 10) {
		printf("> %s\n(0) Cancel\n", msg);
		for (j=0; j<i; j++)
			printf("(%d) %s\n", j+1, sav_elems[j]);
	}
	else {
		printf("> %s\n( 0) Cancel\n", msg);
		if (i < 20)
			for (j=0; j<i; j++)
				printf("(%2d) %s\n", j+1, sav_elems[j]);
		else {
			if (i < 40)
				for (j=0; j<i-1; j += 2)
					printf("(%2d) %-34s (%2d) %s\n", j+1, sav_elems[j], j+2, sav_elems[j+1]);
			else
				for (j=0; j<i-3; j += 4)
					printf("(%2d) %-14s (%2d) %-14s (%2d) %-14s (%2d) %s\n",
					       j+1, sav_elems[j], j+2, sav_elems[j+1], j+3, sav_elems[j+2], j+4, sav_elems[j+3]);
			if (j < i) {
				while (j < i) {
					printf("(%2d) %-14s ", j+1, sav_elems[j]);
					j++;
				}
				printf("\n");
			}
		}
	}

	printf("? "); 

	j = get_int_response();

	if (j == 0)
		return RETURN_BACK;

	if (j >= 1 && j <= i) {
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


enum return_type ask_from_entries(char *msg, char ** questions, char *** answers, int entry_size, void (*callback_func)(char ** strings))
{
	int j, i = 0;
	char ** already_answers = NULL;

	printf("> %s\n", msg);

	while (questions && *questions) {
		printf("(%c) %s\n", i + 'a', *questions);
		i++;
		questions++;
	}

	if (*answers == NULL)
		*answers = (char **) malloc(sizeof(char *) * i);
	else
		already_answers = *answers;

	while (1) {
		int r;
		for (j = 0 ; j < i ; j++) {
			printf("(%c) ? ", j + 'a');
			if (already_answers && *already_answers) {
				(*answers)[j] = get_string_response(*already_answers);
				already_answers++;
			} else
				(*answers)[j] = get_string_response(NULL);

		}
		printf("(0) Cancel (1) Accept (2) Re-enter answers\n? ");
		r = get_int_response();
		if (r == 0)
			return RETURN_BACK;
		if (r == 1)
			return RETURN_OK;
	}
}
