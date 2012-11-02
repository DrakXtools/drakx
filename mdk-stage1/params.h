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

#ifndef _PARAMS_H_
#define _PARAMS_H_

void process_cmdline(void);
int get_param(int i);
const char * get_param_valued(const char *param_name);
void set_param(int i);
void unset_param(int i);
void unset_automatic(void);

struct param_elem
{
	const char * name;
	const char * value;
};

#endif
