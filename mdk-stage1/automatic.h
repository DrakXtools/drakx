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
 * This is supposed to replace the redhat "kickstart", by name but
 * also by design (no code pollution).
 *
 */

#ifndef _AUTOMATIC_H_
#define _AUTOMATIC_H_

#include "stage1.h"

void grab_automatic_params(char * line);
char * get_auto_value(char * auto_param);

enum return_type ask_from_list_auto(char *msg, char ** elems, char ** choice, char * auto_param, char ** elems_auto);
enum return_type ask_from_list_comments_auto(char *msg, char ** elems, char ** elems_comments, char ** choice, char * auto_param, char ** elems_auto);
enum return_type ask_from_entries_auto(char *msg, char ** questions, char *** answers, int entry_size, char ** questions_auto, void (*callback_func)(char ** strings));

#endif
