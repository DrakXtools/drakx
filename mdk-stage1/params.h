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

#ifndef _PARAMS_H_
#define _PARAMS_H_

void process_cmdline(void);
int get_param(int i);
char * get_param_valued(char *param_name);
void set_param(int i);
void unset_param(int i);
void unset_automatic(void);

struct param_elem
{
	char * name;
	char * value;
};

#endif
