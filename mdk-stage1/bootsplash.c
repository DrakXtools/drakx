/*
 * Pixel (pixel@mandrakesoft.com)
 *
 * Copyright 2004 Mandrakesoft
 *
 * This software may be freely redistributed under the terms of the GNU
 * public license.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 *
 */

#include <stdio.h>
#include "bootsplash.h"
#include "frontend.h"
#include "log.h"

static int total_size;
static float previous;
static FILE* splash = NULL;

static void update_progression_only(int current_size)
{
	if (splash && total_size) {
		float ratio = (float) (current_size + 1) / total_size;
		if (ratio > previous + 0.01) {
			fprintf(splash, "show %d\n", (int) (ratio * 65534));
			fflush(splash);
			previous = ratio;
		}
	}
}

static void open_bootsplash(void)
{
	if (!splash) splash = fopen("/proc/splash", "w");
	if (!splash) log_message("opening /proc/splash failed");
}

void exit_bootsplash(void)
{
	log_message("exiting bootsplash");
	open_bootsplash();
	if (splash) {
		fprintf(splash, "verbose\n");
		fflush(splash);
	}
}


void init_progression(char *msg, int size)
{
	previous = 0; total_size = size;
	open_bootsplash();
	update_progression_only(0);
	init_progression_raw(msg, size);
}

void update_progression(int current_size)
{
	update_progression_only(current_size);
	update_progression_raw(current_size);
}

void end_progression(void)
{
	end_progression_raw();
}
