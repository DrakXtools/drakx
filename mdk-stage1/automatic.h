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
 * This is supposed to replace the redhat "kickstart", by name but
 * also by design (no code pollution).
 *
 */

#ifndef _AUTOMATIC_H_
#define _AUTOMATIC_H_

#include "stage1.h"
#include "frontend.h"

void grab_automatic_params(const char * line);
const char * get_auto_value(const char * auto_param);

enum return_type ask_from_list_auto(const char *msg, const char ** elems, char ** choice, const char * auto_param, const char ** elems_auto);
enum return_type ask_from_list_comments_auto(const char *msg, const char ** elems, const char ** elems_comments, char ** choice, const char * auto_param, const char ** elems_auto);
enum return_type ask_from_entries_auto(const char *msg, const char ** questions, char *** answers, int entry_size, const char ** questions_auto, void (*callback_func)(char ** strings));

#endif
