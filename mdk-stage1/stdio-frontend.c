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

#include <probing.h>

#include "frontend.h"


void init_frontend(char * welcome_msg)
{
	printf(welcome_msg);
	printf("\n");
}


void finish_frontend(void)
{
}

static void get_any_response(void)
{
	unsigned char t;
	printf("\n\t(press <enter> to proceed)");
	fflush(stdout);
	read(0, &t, 1);
	fcntl(0, F_SETFL, O_NONBLOCK);
	while (read(0, &t, 1) > 0);
	fcntl(0, F_SETFL, 0);
}
	
static int get_int_response(void)
{
	char s[50];
	int j = 0;
	unsigned int i = 0; /* (0) tied to Cancel */
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
	char s[500];
	int i = 0;
	char buf[10];
	int b_index = 0;
	char b;

	struct termios t;

	memset(s, '\0', sizeof(s));

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
		if (read(0, &b, 1) > 0) {
			if (b_index == 1) {
				if (b == 91) {
					buf[b_index] = b;
					b_index++;
					continue;
				}
				else
					b_index = 0;
			}
			if (b_index == 2) {
				if (b == 67) {
					if (s[i] != '\0') {
						printf("\033[C");
						i++;
					}
				}
				if (b == 68) {
					if (i > 0) {
						printf("\033[D");
						i--;
					}
				}
				b_index = 0;
				continue;
			}
				
			if (b == 13)
				break;
			if (b == 127) {
				if (i > 0) {
					printf("\033[D");
					printf(" ");
					printf("\033[D");
					if (s[i] == '\0')
						s[i-1] = '\0';
					else
						s[i-1] = ' ';
					i--;
				}
			} else if (b == 27) {
				buf[b_index] = b;
				b_index++;
			} else {
				printf("%c", b);
				s[i] = b;
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
	return strdup(s);
}

static void blocking_msg(char *type, char *fmt, va_list ap)
{
	printf(type);
	vprintf(fmt, ap);
	get_any_response();
}

void verror_message(char *msg, va_list ap)
{
	blocking_msg("> Error! ", msg, ap);
}

void vinfo_message(char *msg, va_list ap)
{
	blocking_msg("> Notice: ", msg, ap);
}

void vwait_message(char *msg, va_list ap)
{
	printf("Please wait: ");
	vprintf(msg, ap);
	fflush(stdout);
}

void remove_wait_message(void)
{
	printf("\n");
}


static int size_progress;
static int actually_drawn;
#define PROGRESS_SIZE 45
void init_progression_raw(char *msg, int size)
{
	int i;
	size_progress = size;
	printf("%s  ", msg);
	if (size) {
		actually_drawn = 0;
		for (i=0; i<PROGRESS_SIZE; i++)
			printf(".");
		printf("]\033[G%s [", msg);		/* only works on ANSI-compatibles */
		fflush(stdout);
	} else
		printf("\n");
}

void update_progression_raw(int current_size)
{
	if (size_progress) {
		if (current_size > size_progress)
			current_size = size_progress;
		while ((int)((current_size*PROGRESS_SIZE)/size_progress) > actually_drawn) {
			printf("*");
			actually_drawn++;
		}
	} else
		printf("\033[GStatus: [%8d] bytes loaded...", current_size);
	
	fflush(stdout);
}

void end_progression_raw(void)
{
	if (size_progress) {
		update_progression_raw(size_progress);
		printf("]\n");
	} else
		printf(" done.\n");
}


enum return_type ask_from_list_index(char *msg, char ** elems, char ** elems_comments, int *answer)
{
	int justify_number = 1;
	void print_choice_number(int i) {
		char tmp[500];
		snprintf(tmp, sizeof(tmp), "[%%%dd]", justify_number);
		printf(tmp, i);
	}
	char ** sav_elems = elems;
	int i = 1;
	int j = 0;

	while (elems && *elems) {
		elems++;
		i++;
	}
	if (i >= 10)
		justify_number = 2;

	elems = sav_elems;
	i = 1;

	printf("> %s\n", msg);
	print_choice_number(0);
	printf(" Cancel");

	while (elems && *elems) {
		if (elems_comments && *elems_comments) {
			printf("\n");
			print_choice_number(i);
			printf(" %s (%s)", *elems, *elems_comments);
			j = 0;
		} else {
			if (j == 0)
				printf("\n");
			print_choice_number(i);
			printf(" %-14s ", *elems);
			j++;
		}
		if (j == 4)
			j = 0;
		
		if (elems_comments)
			elems_comments++;
		i++;
		elems++;
	}

	printf("\n? "); 

	j = get_int_response();

	if (j == 0)
		return RETURN_BACK;

	if (j >= 1 && j <= i) {
		*answer = j - 1;
		return RETURN_OK;
	}

	return RETURN_ERROR;
}


enum return_type ask_yes_no(char *msg)
{
	int j;

	printf("> %s\n[0] Yes  [1] No  [2] Back\n? ", msg);

	j = get_int_response();

	if (j == 0)
		return RETURN_OK;
	else if (j == 2)
		return RETURN_BACK;
	else return RETURN_ERROR;
}


enum return_type ask_from_entries(char *msg, char ** questions, char *** answers, int entry_size UNUSED, void (*callback_func)(char ** strings) UNUSED)
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
		printf("[0] Cancel  [1] Accept  [2] Re-enter answers\n? ");
		r = get_int_response();
		if (r == 0)
			return RETURN_BACK;
		if (r == 1)
			return RETURN_OK;
	}
}


void suspend_to_console(void) {}
void resume_from_suspend(void) {}
