/* Copyright (C) 2012 Mandriva
   Written by Per Øyvind Karlsen <peroyvind@mandriva.org>, 2012
   Based on code by Guillaume Cottenceau <gc@mandriva.com>, 2000-2005.

   This program is free software; you can redistribute it and/or modify
   it under the terms of the GNU General Public License as published by
   the Free Software Foundation; either version 2, or (at your option)
   any later version.

   This program is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
   GNU General Public License for more details.

   You should have received a copy of the GNU General Public License
   along with this program; if not, write to the Free Software Foundation,
   Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.  */

#include <stdio.h>
#include <stdlib.h>
#include <stdbool.h>
#include <errno.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/utsname.h>
#include <limits.h>
#include <string.h>

#include <libldetect.h>

#include "drvinst.h"
#include "modules.h"

/* TODO: add_addons... */
static void load_modules(int argc, char *argv[]) {
    struct pciusb_entries entries = pci_probe();
    unsigned int i;

    for (i = 0; i < entries.nb; i++) {
	struct pciusb_entry *e = &entries.entries[i];
	const char *class = pci_class2text(e->class_id);
	if (!e->module || strchr(e->module, ':') || !strcmp(class, "DISPLAY_VGA"))
	    continue;
	if (argc > 1) {
	    int j;
	    bool skip = true;
	    for (j = 1; j < argc; j++) {
		if (!strncasecmp(argv[j], class, strlen(argv[j]))) {
		    skip = false;
		    break;
		}
	    }
	    if (skip)
		continue;
	}
	printf("Installing driver %s (for \"%s\" [%s])\n", e->module, e->text, class);
	modprobe(e->module, NULL);
    }
    pciusb_free(&entries);
}

int drvinst_main(int argc, char *argv[]) {
    if (argc > 1 && !strcmp(argv[0], "--help")) 
	fprintf(stderr, "usage: drivers_install [drivertype1 [drivertype2 ...]]\n");
    else
	load_modules(argc, argv);
    return 0;
}
