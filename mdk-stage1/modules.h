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

#ifndef _MODULES_H_
#define _MODULES_H_

#include "stage1.h"
#include "probing.h"

void init_modules_insmoding(void);
int my_insmod(const char * mod_name, enum driver_type type, char * options);
enum return_type ask_insmod(enum driver_type);

struct module_deps_elem {
    char * name;
    char ** deps;
};



#endif
