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
 * Using high-level UI.
 *
 * These functions are frontend-independant: your program won't know each
 * `frontend' (e.g. each way to grab user input) will be used.
 *
 * Then you may link your binary against any `frontend' that implement all
 * these functions (and possibly necessary libraries).
 */


#ifndef _FRONTEND_H_
#define _FRONTEND_H_

/* this must be called before anything else */
void init_frontend(void);

/* this must be called before exit of program */
void finish_frontend(void);


void info_message(char *msg, ...) __attribute__ ((format (printf, 1, 2))); /* (blocks program) */

void error_message(char *msg, ...) __attribute__ ((format (printf, 1, 2))); /* (blocks program) */

/* (doesn't block program) 
 * (this is not necessarily stackable, e.g. only one wait_message at a time) */
void wait_message(char *msg, ...) __attribute__ ((format (printf, 1, 2)));

/* call this to finish the wait on wait_message */
void remove_wait_message(void);

/* monitor progression of something (downloading a file, etc)
 * if size of progression is unknown, use `0' */
void init_progression(char *msg, int size);
void update_progression(int current_size);
void end_progression(void);

enum frontend_return { RETURN_OK, RETURN_BACK, RETURN_ERROR };

/* Yes == RETURN_OK    No == RETURN_ERROR    Back == RETURN_BACK */
enum frontend_return ask_yes_no(char *msg);

/* [elems] NULL terminated array of char*
 * [choice] address of a (unitialized) char* */
enum frontend_return ask_from_list(char *msg, char ** elems, char ** choice);

enum frontend_return ask_from_list_comments(char *msg, char ** elems, char ** elems_comments, char ** choice);

/* [questions] NULL terminated array of char*
 * [answers] address of a (unitialized) char**, will contain a non-NULL terminated array of char*
 * [callback_func] function called at most when the answers change; it can examine the array of char* and assign some new char* */
enum frontend_return ask_from_entries(char *msg, char ** questions, char *** answers, int entry_size, void (*callback_func)(char ** strings));

#endif
