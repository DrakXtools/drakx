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

/*
 * For doc please read doc/documented..frontend.h
 */

#ifndef _FRONTEND_H_
#define _FRONTEND_H_

#include <stdarg.h>

/* 'unused' atttribute, gcc specific and just to turn down some warnings.  */
#if defined __GNUC__
#define UNUSED __attribute__((unused))
#else
#define UNUSED
#endif

enum return_type { RETURN_OK, RETURN_BACK, RETURN_ERROR };

void init_frontend(const char * welcome_msg);
void finish_frontend(void);

void error_message(const char *msg, ...) __attribute__ ((format (printf, 1, 2))); /* blocking */
void info_message(const char *msg, ...) __attribute__ ((format (printf, 1, 2))); /* blocking */
void wait_message(const char *msg, ...) __attribute__ ((format (printf, 1, 2))); /* non-blocking */
void remove_wait_message(void);

void init_progression_raw(const char *msg, int size);
void update_progression_raw(int current_size);
void end_progression_raw(void);

#ifdef ENABLE_BOOTSPLASH
void init_progression(const char *msg, int size);
void update_progression(int current_size);
void end_progression(void);
#else
#define init_progression init_progression_raw
#define update_progression update_progression_raw
#define end_progression end_progression_raw
#endif

enum return_type ask_yes_no(const char *msg);
enum return_type ask_from_list_index(const char *msg, const char ** elems, const char ** elems_comments, int *answer);
enum return_type ask_from_list(const char *msg, const char ** elems, char ** choice);
enum return_type ask_from_list_comments(const char *msg, const char ** elems, const char ** elems_comments, char ** choice);
enum return_type ask_from_entries(const char *msg, const char ** questions, char *** answers, int entry_size, void (*callback_func)(char ** strings));

void suspend_to_console(void);
void resume_from_suspend(void);

void verror_message(const char *msg, va_list ap);
void vinfo_message(const char *msg, va_list ap);
void vwait_message(const char *msg, va_list ap);

extern const char * binary_name;
extern int size_progress;
extern int actually_drawn;

#endif
