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

/*
 * Portions from Erik Troan (ewt@redhat.com)
 *
 * Copyright 1996 Red Hat Software 
 *
 */

#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <sys/types.h>
#include "log.h"

#include "mount.h"


int my_mount(char *dev, char *location, char *fs)
{
	unsigned long flags;
	char * opts = NULL;
	struct stat buf;

	log_message("mounting %s on %s as type %s", dev, location, fs);

	if (stat(location, &buf)) {
		log_message("creating dir %s", location);
		if (mkdir(location, 0755)) {
			log_message("could not create location dir");
			return -1;
		}
	} else if (!S_ISDIR(buf.st_mode)) {
		log_message("not a dir %s, will unlink and mkdir", location);
		if (unlink(location)) {
			log_message("could not unlink %s", location);
			return -1;
		}
		if (mkdir(location, 0755)) {
			log_message("could not create location dir");
			return -1;
		}
	}

	flags = MS_MGC_VAL;

	if (!strcmp(fs, "vfat"))
		opts = "check=relaxed";
	
	if (!strcmp(fs, "iso9660"))
		flags |= MS_RDONLY;

	return mount(dev, location, fs, flags, opts);
}
