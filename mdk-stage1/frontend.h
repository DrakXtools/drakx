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
 * For doc please read doc/documented..frontend.h
 */

#ifndef _FRONTEND_H_
#define _FRONTEND_H_

#include <stdarg.h>


enum return_type { RETURN_OK, RETURN_BACK, RETURN_ERROR };

void init_frontend(char * welcome_msg);
void finish_frontend(void);

void error_message(char *msg, ...) __attribute__ ((format (printf, 1, 2))); /* blocking */
void info_message(char *msg, ...) __attribute__ ((format (printf, 1, 2))); /* blocking */
void wait_message(char *msg, ...) __attribute__ ((format (printf, 1, 2))); /* non-blocking */
void remove_wait_message(void);

void init_progression(char *msg, int size);
void update_progression(int current_size);
void end_progression(void);

enum return_type ask_yes_no(char *msg);
enum return_type ask_from_list(char *msg, char ** elems, char ** choice);
enum return_type ask_from_list_comments(char *msg, char ** elems, char ** elems_comments, char ** choice);
enum return_type ask_from_entries(char *msg, char ** questions, char *** answers, int entry_size, void (*callback_func)(char ** strings));

void suspend_to_console(void);
void resume_from_suspend(void);

void verror_message(char *msg, va_list ap);
void vinfo_message(char *msg, va_list ap);
void vwait_message(char *msg, va_list ap);


#endif
