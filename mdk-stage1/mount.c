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
	int major, minor;
	int type = S_IFBLK; /* my default type is block. don't forget to change for chars */
	const char * name;
	struct stat buf;
	char * ptr;
	
	name = &dev[5]; /* we really need that dev be passed as /dev/something.. */

	if (!stat(dev, &buf))
		return 0; /* if the file already exists, we assume it's correct */

	if (ptr_begins_static_str(name, "sd")) {
		/* SCSI disks */
		major = 8;
		minor = (name[2] - 'a') << 4;
		if (name[3] && name[4])
			minor += 10 + (name[4] - '0');
		else if (name[3])
			minor += (name[3] - '0');
	} else if (ptr_begins_static_str(name, "hd")) {
		/* IDE disks/cd's */
		if (name[2] == 'a')
			major = 3, minor = 0;
		else if (name[2] == 'b')
			major = 3, minor = 64;
		else if (name[2] == 'c')
			major = 22, minor = 0;
		else if (name[2] == 'd')
			major = 22, minor = 64;
		else if (name[2] == 'e')
			major = 33, minor = 0;
		else if (name[2] == 'f')
			major = 33, minor = 64;
		else if (name[2] == 'g')
			major = 34, minor = 0;
		else if (name[2] == 'h')
			major = 34, minor = 64;
		else if (name[2] == 'i')
			major = 56, minor = 0;
		else if (name[2] == 'j')
			major = 56, minor = 64;
		else if (name[2] == 'k')
			major = 57, minor = 0;
		else if (name[2] == 'l')
			major = 57, minor = 64;
		else if (name[2] == 'm')
			major = 88, minor = 0;
		else if (name[2] == 'n')
			major = 88, minor = 64;
		else if (name[2] == 'o')
			major = 89, minor = 0;
		else if (name[2] == 'p')
			major = 89, minor = 64;
		else if (name[2] == 'q')
			major = 90, minor = 0;
		else if (name[2] == 'r')
			major = 90, minor = 64;
		else if (name[2] == 's')
			major = 91, minor = 0;
		else if (name[2] == 't')
			major = 91, minor = 64;
		else
			return -1;
		
		if (name[3] && name[4])
			minor += 10 + (name[4] - '0');
		else if (name[3])
			minor += (name[3] - '0');
	} else if (ptr_begins_static_str(name , "sr")) {
		/* SCSI cd's */
		major = 11;
		minor = name[2] - '0';
	} else if (ptr_begins_static_str(name, "ida/") ||
		   ptr_begins_static_str(name, "cciss/")) {
		/* Compaq Smart Array "ida/c0d0{p1}" */
		ptr = strchr(name, '/');
		mkdir("/dev/ida", 0755);
		mkdir("/dev/cciss", 0755);
		major = ptr_begins_static_str(name, "ida/") ? 72 : 104 + charstar_to_int(ptr+2);
		ptr = strchr(ptr, 'd');
		minor = 16 * charstar_to_int(ptr+1);
		ptr = strchr(ptr, 'p');
		minor += charstar_to_int(ptr+1);
	} else if (ptr_begins_static_str(name, "rd/")) {
		/* DAC960 "rd/cXdXXpX" */
		mkdir("/dev/rd", 0755);
		major = 48 + charstar_to_int(name+4);
		ptr = strchr(name+4, 'd');
		minor = 8 * charstar_to_int(ptr+1);
		ptr = strchr(ptr, 'p');
		minor += charstar_to_int(ptr+1);
	} else if (ptr_begins_static_str(name, "loop")) {
		major = 7;
		minor = name[4] - '0';
	} else if (ptr_begins_static_str(name, "chloop")) {
		major = 100;
		minor = name[6] - '0';
	} else {
		log_message("I don't know how to create device %s, please post bugreport to me!", dev);
		return -1;
	}

	if (mknod(dev, type | 0600, makedev(major, minor))) {
		log_perror(dev);
		return -1;
	}
	
	return 0;
}


/* mounts, creating the device if needed+possible */
int my_mount(char *dev, char *location, char *fs, int force_rw)
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

	if (!strcmp(fs, "supermount")) {
		my_insmod("supermount", ANY_DRIVER_TYPE, NULL, 1);
		my_insmod("isofs", ANY_DRIVER_TYPE, NULL, 1);
		opts = alloca(500);
                sprintf(opts, "dev=%s,fs=iso9660,tray_lock=always", dev);
                dev = "none";
	}

#ifndef DISABLE_MEDIAS
	if (!strcmp(fs, "vfat")) {
		my_insmod("vfat", ANY_DRIVER_TYPE, NULL, 1);
		opts = "check=relaxed";
	}

	if (!strcmp(fs, "ntfs")) {
		my_insmod("ntfs", ANY_DRIVER_TYPE, NULL, 1);
	}

	if (!strcmp(fs, "reiserfs"))
		my_insmod("reiserfs", ANY_DRIVER_TYPE, NULL, 1);

	if (!strcmp(fs, "jfs"))
		my_insmod("jfs", ANY_DRIVER_TYPE, NULL, 1);

	if (!strcmp(fs, "xfs"))
		my_insmod("xfs", ANY_DRIVER_TYPE, NULL, 1);

#endif
	if (!strcmp(fs, "iso9660"))
		my_insmod("isofs", ANY_DRIVER_TYPE, NULL, 1);

#ifndef DISABLE_NETWORK
	if (!strcmp(fs, "nfs")) {
		my_insmod("nfs", ANY_DRIVER_TYPE, NULL, 1);
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
