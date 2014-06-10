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

/*
 * Portions from Erik Troan (ewt@redhat.com)
 *
 * Copyright 1996 Red Hat Software 
 *
 */

#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <stdio.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <sys/types.h>
#include "log.h"
#include "utils.h"
#include "modules.h"

#include "mount.h"



/* WARNING: this won't work if the argument is not /dev/ based */
int ensure_dev_exists(const char * dev)
{
	struct stat buf;

	if (!stat(dev, &buf))
		return 0; /* if the file already exists, we assume it's correct */

	// give udev some time to create nodes if module was just insmoded:
	system("udevadm settle");

	if (!stat(dev, &buf)) {
		log_message("I don't know how to create device %s, please post bugreport to me!", dev);
		return -1;
	}

	return 0;
}


/* mounts, creating the device if needed+possible */
int my_mount(const char *dev, const char *location, const char *fs, int force_rw)
{
	unsigned long flags = MS_MGC_VAL | (force_rw ? 0 : MS_RDONLY);
	char * opts = NULL;
	struct stat buf;
	int rc;

	if (strcmp(fs, "nfs")) {
	    rc = ensure_dev_exists(dev);
	    if (rc != 0) {
		    log_message("could not create required device file");
		    return -1;
	    }
	}

	log_message("mounting %s on %s as type %s", dev, location, fs);

	if (stat(location, &buf)) {
		if (mkdir(location, 0755)) {
			log_perror("could not create location dir");
			return -1;
		}
	} else if (!S_ISDIR(buf.st_mode)) {
		log_message("not a dir %s, will unlink and mkdir", location);
		if (unlink(location)) {
			log_perror("could not unlink");
			return -1;
		}
		if (mkdir(location, 0755)) {
			log_perror("could not create location dir");
			return -1;
		}
	}

#ifndef DISABLE_MEDIAS
	if (!strcmp(fs, "vfat")) {
		my_modprobe("nls_cp437", ANY_DRIVER_TYPE, NULL);
		my_modprobe("nls_iso8859_1", ANY_DRIVER_TYPE, NULL);
		my_modprobe("vfat", ANY_DRIVER_TYPE, NULL);
		opts = (char*)"check=relaxed";
	}

	if (!strcmp(fs, "ntfs")) {
		my_modprobe("ntfs", ANY_DRIVER_TYPE, NULL);
	}

	if (!strcmp(fs, "reiserfs"))
		my_modprobe("reiserfs", ANY_DRIVER_TYPE, NULL);

	if (!strcmp(fs, "reiser4"))
		my_modprobe("reiser4", ANY_DRIVER_TYPE, NULL);

	if (!strcmp(fs, "jfs"))
		my_modprobe("jfs", ANY_DRIVER_TYPE, NULL);

	if (!strcmp(fs, "xfs"))
		my_modprobe("xfs", ANY_DRIVER_TYPE, NULL);

	if (!strcmp(fs, "ext4"))
		my_modprobe("ext4", ANY_DRIVER_TYPE, NULL);

	if (!strcmp(fs, "btrfs"))
		my_modprobe("btrfs", ANY_DRIVER_TYPE, NULL);

#endif
	if (!strcmp(fs, "iso9660"))
		my_modprobe("isofs", ANY_DRIVER_TYPE, NULL);

#ifndef DISABLE_NETWORK
	if (!strcmp(fs, "nfs")) {
		my_modprobe("nfs", ANY_DRIVER_TYPE, NULL);
		log_message("preparing nfsmount for %s", dev);
		rc = nfsmount_prepare(dev, &opts);
		if (rc != 0)
			return rc;
	}
#endif

	rc = mount(dev, location, fs, flags, opts);
	if (rc != 0) {
		log_perror("mount failed");
		rmdir(location);
	}

	return rc;
}
