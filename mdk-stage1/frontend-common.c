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

#include <stdlib.h>
#include <stdarg.h>

#include "frontend.h"


void info_message(char *msg, ...)
{
	va_list args;
	probe_that_type(USB_CONTROLLERS, BUS_USB); // we'd need the keyboard for interactions so...
	va_start(args, msg);
	vinfo_message(msg, args);
	va_end(args);
}

void wait_message(char *msg, ...)
{
	va_list args;
	va_start(args, msg);
	vwait_message(msg, args);
	va_end(args);
}

void error_message(char *msg, ...)
{
	va_list args;
	probe_that_type(USB_CONTROLLERS, BUS_USB); // we'd need the keyboard for interactions so...
	va_start(args, msg);
	verror_message(msg, args);
	va_end(args);
}
