/*
 * Original author:
 * Guillaume Cottenceau <gc@mandriva.com>
 *
 * Current maintainer:
 * Per Øyvind Karlsen <peroyvind@mandriva.org>
 * Copyright 2000-2012 Mandriva
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

#include <stdbool.h>
#include <string>

#include "stage1.h"
#include "probing.h"
#include "frontend.h"

enum insmod_return { INSMOD_OK, INSMOD_FAILED, INSMOD_FAILED_FILE_NOT_FOUND };

void init_modules_insmoding(void);

int insmod(const char *filename, const char *options);
int modprobe(const char *alias, const char *extra_options);

enum insmod_return my_modprobe(const char * mod_name, enum driver_type type, const char * options);
enum return_type ask_insmod(enum driver_type);
bool module_already_present(const char * name);
bool module_exists(const std::string &name);

extern int disable_modules;

#endif
