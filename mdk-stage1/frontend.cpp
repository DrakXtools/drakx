/*
 * Per Øyvind Karlsen (peroyvind@mandriva.org)
 *
 * Copyright 2012 Mandriva
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


#define _GNU_SOURCE 1
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
#include "utils.h"

int size_progress;
int actually_drawn;

/* really ugly for now... */
#include "stdio-frontend.cpp"
#include "newt-frontend.cpp"

void init_frontend(const char * welcome_msg)
{
    if (!strcmp(binary_name, "probe-modules"))
	init_frontend_stdio(welcome_msg);
    else
	init_frontend_newt(welcome_msg);
}


void finish_frontend(void)
{
    if (!strcmp(binary_name, "probe-modules"))
	finish_frontend_stdio();
    else
	finish_frontend_newt();
}

void verror_message(const char *msg, va_list ap)
{
    if (!strcmp(binary_name, "probe-modules"))
	verror_message_stdio(msg, ap);
    else
	verror_message_newt(msg, ap);
}

void vinfo_message(const char *msg, va_list ap)
{
    if (!strcmp(binary_name, "probe-modules"))
	vinfo_message_stdio(msg, ap);
    else
	vinfo_message_newt(msg, ap);
}

void vwait_message(const char *msg, va_list ap)
{
    if (!strcmp(binary_name, "probe-modules"))
	vwait_message_stdio(msg, ap);
    else
	vwait_message_newt(msg, ap);
}

void remove_wait_message(void)
{
    if (!strcmp(binary_name, "probe-modules"))
	remove_wait_message_stdio();
    else
	remove_wait_message_newt();
}


void init_progression_raw(const char *msg, int size)
{
    if (!strcmp(binary_name, "probe-modules"))
	init_progression_raw_stdio(msg, size);
    else
	init_progression_raw_newt(msg, size);
}

void update_progression_raw(int current_size)
{
    if (!strcmp(binary_name, "probe-modules"))
	update_progression_raw_stdio(current_size);
    else
	update_progression_raw_newt(current_size);
}

void end_progression_raw(void)
{
    if (!strcmp(binary_name, "probe-modules"))
	end_progression_raw_stdio();
    else
	end_progression_raw_newt();
}


enum return_type ask_from_list_index(const char *msg, const char ** elems, const char ** elems_comments, int *answer)
{
    if (!strcmp(binary_name, "probe-modules"))
	return ask_from_list_index_stdio(msg, elems, elems_comments, answer);
    else
	return ask_from_list_index_newt(msg, elems, elems_comments, answer);
}

enum return_type ask_yes_no(const char *msg)
{
    if (!strcmp(binary_name, "probe-modules"))
	return ask_yes_no_stdio(msg);
    else
	return ask_yes_no_newt(msg);
}

enum return_type ask_from_entries(const char *msg, const char ** questions, char *** answers, int entry_size UNUSED, void (*callback_func)(char ** strings) UNUSED)
{
    if (!strcmp(binary_name, "probe-modules"))
	return ask_from_entries_stdio(msg, questions, answers, entry_size, callback_func);
    else
	return ask_from_entries_newt(msg, questions, answers, entry_size, callback_func);
}


void suspend_to_console(void) {
    if (!strcmp(binary_name, "probe-modules"))
	return suspend_to_console_stdio();
    else
	return suspend_to_console_newt();

}
void resume_from_suspend(void) {
    if (!strcmp(binary_name, "probe-modules"))
	return resume_from_suspend_stdio();
    else
	return resume_from_suspend_newt();
}
