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

#ifndef _MODULES_H_
#define _MODULES_H_

#include "stage1.h"
#include "probing.h"

enum insmod_return { INSMOD_OK, INSMOD_FAILED, INSMOD_FAILED_FILE_NOT_FOUND };

void init_modules_insmoding(void);
void init_firmware_timeout(void);
int insmod_local_file(char * path, char * options);
enum insmod_return my_insmod(const char * mod_name, enum driver_type type, char * options, int allow_modules_floppy);
enum return_type ask_insmod(enum driver_type);
int module_already_present(const char * name);

struct module_deps_elem {
    char * modname;
    char * filename;
    char ** deps;
};

struct module_descr_elem {
    char * modname;
    char * description;
};

extern int disable_modules;

#endif
