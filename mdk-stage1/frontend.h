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
 * Each different frontend must implement all functions defined here
 */


#ifndef _FRONTEND_H_
#define _FRONTEND_H_

#include "stage1.h"

void init_frontend(void);
void finish_frontend(void);
void error_message(char *msg);
void wait_message(char *msg, ...);
void remove_wait_message(void);

enum return_type ask_yes_no(char *msg);
enum return_type ask_from_list(char *msg, char ** elems, char ** choice);
enum return_type ask_from_list_comments(char *msg, char ** elems, char ** elems_comments, char ** choice);

#endif
