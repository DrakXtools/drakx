/*
 * Per Øyvind Karlsen <proyvind@moonmdrake.org>
 *
 * Copyright 2017 Moondrake
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
 * For doc please read doc/documented..frontend.h
 */

#ifndef _STDIO_FRONTEND_H_
#define _STDIO_FRONTEND_H_

void init_frontend_stdio(const char * welcome_msg);
const void finish_frontend_stdio(void);

void remove_wait_message_stdio(void);

void init_progression_raw_stdio(const char *msg, int size);
void update_progression_raw_stdio(int current_size);
void end_progression_raw_stdio(void);

enum return_type ask_yes_no_stdio(const char *msg);
enum return_type ask_from_list_index_stdio(const char *msg, const char ** elems, const char ** elems_comments, int *answer);
enum return_type ask_from_entries_stdio(const char *msg, const char ** questions, char *** answers, int entry_size, void (*callback_func)(char ** strings));

void suspend_to_console_stdio(void);
void resume_from_suspend_stdio(void);

void verror_message_stdio(const char *msg, va_list ap);
void vinfo_message_stdio(const char *msg, va_list ap);
void vwait_message_stdio(const char *msg, va_list ap);

#endif
