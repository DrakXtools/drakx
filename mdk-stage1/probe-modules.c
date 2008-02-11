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

void exit_bootsplash(void) {}
void stg1_error_message(char *msg, ...)
{
	va_list args;
	va_start(args, msg);
	verror_message(msg, args);
	va_end(args);
}
void fatal_error(char *msg)
{
	log_message("FATAL ERROR IN MODULES LOADER: %s\n\nI can't recover from this.\nYou may reboot your system.\n", msg);
	exit(EXIT_FAILURE);
}

int main(int argc, char **argv, char **env)
{
	enum media_bus bus = BUS_ANY;
	char *module = NULL;

	if (argc > 1) {
		if (streq(argv[1], "--usb")) {
			bus = BUS_USB;
		} else if (!ptr_begins_static_str(argv[1], "--")) {
			module = argv[1];
		}
	}

	open_log();
	init_modules_insmoding();

	if (module) {
		my_insmod(module, ANY_DRIVER_TYPE, NULL, 0);
	} else {
		find_media(bus);
	}

	close_log();

	return 0;
}
