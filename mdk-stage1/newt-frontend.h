/*
 * Per Øyvind Karlsen <proyvind@moondrake.org>
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

#ifndef _NEWT_FRONTEND_H_
#define _NEWT_FRONTEND_H_

void init_frontend_newt(const char * welcome_msg);
void finish_frontend_newt(void);

void remove_wait_message_newt(void);

void init_progression_raw_newt(const char *msg, int size);
void update_progression_raw_newt(int current_size);
void end_progression_raw_newt(void);

enum return_type ask_yes_no_newt(const char *msg);
enum return_type ask_from_list_index_newt(const char *msg, const char ** elems, const char ** elems_comments, int *answer);
enum return_type ask_from_entries_newt(const char *msg, const char ** questions, char *** answers, int entry_size, void (*callback_func)(char ** strings));

void suspend_to_console_newt(void);
void resume_from_suspend_newt(void);

void verror_message_newt(const char *msg, va_list ap);
void vinfo_message_newt(const char *msg, va_list ap);
void vwait_message_newt(const char *msg, va_list ap);

#endif
