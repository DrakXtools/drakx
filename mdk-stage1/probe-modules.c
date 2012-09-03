/*
 * Olivier Blin (blino@mandriva.com)
 *
 * Copyright 2007-2004 Mandriva
 *
 *
 * This software may be freely redistributed under the terms of the GNU
 * public license.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 *
 */

#include "log.h"
#include "modules.h"
#include "probing.h"
#include "frontend.h"
#include <stdlib.h>
#include <sys/stat.h>
#include <string.h>
#include "utils.h"

int probe_modules_main(int argc, char *argv[])
{
	exit(1);
	enum media_bus bus = BUS_ANY;
	char *module = NULL;
	char options[500] = "";

	if (argc > 1) {
		if (streq(argv[1], "--usb")) {
			bus = BUS_USB;
		} else if (!ptr_begins_static_str(argv[1], "--")) {
			int i;
			module = argv[1];
			for (i = 2; i < argc; i++) {
				strcat(options, argv[i]);
				strcat(options, " ");
			}
		}
	}

	open_log();
	init_modules_insmoding();

	if (module) {
		my_insmod(module, ANY_DRIVER_TYPE, options, 0);
	} else {
		find_media(bus);
	}

	close_log();

	return 0;
}
