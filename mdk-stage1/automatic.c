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
 * This is supposed to replace the redhat "kickstart", by name but
 * also by design (less code pollution).
 *
 */


#include <unistd.h>
#include <stdlib.h>
#include <string.h>
#include "tools.h"
#include "stage1.h"
#include "frontend.h"
#include "log.h"

#include "automatic.h"


static struct param_elem * automatic_params;
static char * value_not_bound = "";

void grab_automatic_params(char * line)
{
	int i, p;
	struct param_elem tmp_params[50];

	i = 0; p = 0;
	while (line[i] != '\0') {
		char *name, *value;
		int k;
		int j = i;
		while (line[i] != ':' && line[i] != '\0')
			i++;
		name = memdup(&line[j], i-j + 1);
		name[i-j] = 0;

		k = i+1;
		i++;
		while (line[i] != ',' && line[i] != '\0')
			i++;
		value = memdup(&line[k], i-k + 1);
		value[i-k] = 0;

		tmp_params[p].name = name;
		tmp_params[p].value = value;
		p++;
		if (line[i] == '\0')
			break;
		i++;
	}

	tmp_params[p++].name = NULL;
	automatic_params = memdup(tmp_params, sizeof(struct param_elem) * p);

	log_message("AUTOMATIC MODE: got %d params", p-1);
}


char * get_auto_value(char * auto_param)
{
	struct param_elem * ptr = automatic_params;

	while (ptr->name) {
		if (!strcmp(ptr->name, auto_param))
			return ptr->value;
		ptr++;
	}

	return value_not_bound;
}


enum return_type ask_from_list_auto(char *msg, char ** elems, char ** choice, char * auto_param, char ** elems_auto)
{
	if (!IS_AUTOMATIC)
		return ask_from_list(msg, elems, choice);
	else {
		char ** sav_elems = elems;
		char * tmp = get_auto_value(auto_param);
		while (elems && *elems) {
			if (!strcmp(tmp, *elems_auto)) {
				*choice = *elems;
				log_message("AUTOMATIC: parameter %s for %s means returning %s", tmp, auto_param, *elems);
				return RETURN_OK;
			}
			elems++;
			elems_auto++;
		}
		unset_param(MODE_AUTOMATIC); /* we are in a fallback mode */
		return ask_from_list(msg, sav_elems, choice);
	}
}

enum return_type ask_from_entries_auto(char *msg, char ** questions, char *** answers, int entry_size, char ** questions_auto)
{
	if (!IS_AUTOMATIC)
		return ask_from_entries(msg, questions, answers, entry_size);
	else {
		char * tmp_answers[50];
		int i = 0;
		while (questions && *questions) {
			tmp_answers[i] = get_auto_value(*questions_auto);
			log_message("AUTOMATIC: question %s answers %s because of param %s", *questions, tmp_answers[i], *questions_auto);
			i++;
			questions++;
			questions_auto++;
			
		}
		*answers = memdup(tmp_answers, sizeof(char *) * i);
		return RETURN_OK;
	}
}
