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
#include <stdio.h>
#include <string.h>
#include <sys/mount.h>
#include <dirent.h>
#include "stage1.h"
#include "frontend.h"
#include "modules.h"
#include "probing.h"
#include "log.h"
#include "mount.h"

#include "disk.h"


static char * list_directory(char * direct)
{
	char tmp[500] = "";
	int nb = 0;
	struct dirent *ep;
	DIR *dp = opendir(direct);
	while (dp && nb < 5 && (ep = readdir(dp))) {
		if (strcmp(ep->d_name, ".") && strcmp(ep->d_name, "..")) {
			strcat(tmp, strdup(ep->d_name));
			strcat(tmp, "\n");
			nb++;
		}
	}
	if (dp)
		closedir(dp);
	return strdup(tmp);
}

static enum return_type try_with_device(char *dev_name)
{
	char * questions_location[] = { "Directory", NULL };
	char ** answers_location;
	char device_fullname[50];
	char location_full[500];

	char * disk_own_mount = "/tmp/disk";

	int major, minor, blocks;
	char name[100];

	char buf[512];
	FILE * f;
	char * parts[50];
	char * parts_comments[50];
	int i = 0;
	enum return_type results;
	char * choice;

	if (!(f = fopen("/proc/partitions", "rb")) || !fgets(buf, sizeof(buf), f) || !fgets(buf, sizeof(buf), f)) {
		log_perror(dev_name);
		error_message("Could not read partitions information");
		return RETURN_ERROR;
	}

	while (fgets(buf, sizeof(buf), f)) {
		sscanf(buf, " %d %d %d %s", &major, &minor, &blocks, name);
		if ((strstr(name, dev_name) == name) && (blocks > 1) && (name[strlen(dev_name)] != '\0')) {
			parts[i] = strdup(name);
			parts_comments[i] = (char *) malloc(sizeof(char) * 25);
			snprintf(parts_comments[i], 24, "size: %d Mbytes", blocks >> 10);
			i++;
		}
	}
	parts[i] = NULL;
	fclose(f);

	results = ask_from_list_comments("Please choose the partition where is copied the " DISTRIB_NAME " Distribution.",
					 parts, parts_comments, &choice);
	if (results != RETURN_OK)
		return results;

	strcpy(device_fullname, "/dev/");
	strcat(device_fullname, choice);
	
	if (my_mount(device_fullname, disk_own_mount, "ext2") == -1 &&
	    my_mount(device_fullname, disk_own_mount, "vfat") == -1 &&
	    my_mount(device_fullname, disk_own_mount, "reiserfs") == -1) {
		error_message("I can't find a valid filesystem.");
		return try_with_device(dev_name);
	}

	if (ask_from_entries("Please enter the directory containing the " DISTRIB_NAME " Distribution.",
			     questions_location, &answers_location, 24) != RETURN_OK) {
		umount(disk_own_mount);
		return try_with_device(dev_name);
	}

	strcpy(location_full, disk_own_mount);
	strcat(location_full, "/");
	strcat(location_full, answers_location[0]);

	if (access(location_full, R_OK)) {
		error_message("Directory could not be found on partition.\n"
			      "Here's a short extract of the files in the root of the partition:\n"
			      "%s", list_directory(disk_own_mount));
		umount(disk_own_mount);
		return try_with_device(dev_name);
	}

	unlink(IMAGE_LOCATION);
	symlink(location_full, IMAGE_LOCATION);

	if (IS_SPECIAL_STAGE2 || ramdisk_possible()) {
		/* RAMDISK install */
		if (access(IMAGE_LOCATION RAMDISK_LOCATION, R_OK)) {
			error_message("I can't find the " DISTRIB_NAME " Distribution in the specified directory. "
				      "(I need the directory " RAMDISK_LOCATION ")\n"
				      "Here's a short extract of the files in the directory:\n"
				      "%s", list_directory(IMAGE_LOCATION));
			umount(disk_own_mount);
			unlink(IMAGE_LOCATION);
			return try_with_device(dev_name);
		}
		if (load_ramdisk() != RETURN_OK) {
			error_message("Could not load program into memory");
			return try_with_device(dev_name);
		}
	} else {
		/* LIVE install */
		char p;
		if (access(IMAGE_LOCATION LIVE_LOCATION, R_OK)) {
			error_message("I can't find the " DISTRIB_NAME " Distribution in the specified directory. "
				      "(I need the directory " LIVE_LOCATION ")\n"
				      "Here's a short extract of the files in the directory:\n"
				      "%s", list_directory(IMAGE_LOCATION));
			umount(disk_own_mount);
			unlink(IMAGE_LOCATION);
			return try_with_device(dev_name);
		}
		if (readlink(IMAGE_LOCATION LIVE_LOCATION "/usr/bin/runinstall2", &p, 1) != 1) {
			error_message("The " DISTRIB_NAME " Distribution seems to be copied on a Windows partition. "
				      "You need more memory to perform an installation from a Windows partition. "
				      "Another solution if to copy the " DISTRIB_NAME " Distribution on a Linux partition.");
			umount(disk_own_mount);
			unlink(IMAGE_LOCATION);
			return try_with_device(dev_name);
		}
		log_message("found the " DISTRIB_NAME " Installation, good news!");
	}

	if (IS_RESCUE)
		umount(IMAGE_LOCATION);

	method_name = strdup("disk");
	return RETURN_OK;
}

enum return_type disk_prepare(void)
{
	char ** medias, ** ptr, ** medias_models;
	char * choice;
	int i, count = 0;
	enum return_type results;

	my_insmod("sd_mod", ANY_DRIVER_TYPE, NULL);
	
	get_medias(DISK, &medias, &medias_models);

	ptr = medias;
	while (ptr && *ptr) {
		count++;
		ptr++;
	}

	if (count == 0) {
		error_message("No DISK drive found.");
		i = ask_insmod(SCSI_ADAPTERS);
		if (i == RETURN_BACK)
			return RETURN_BACK;
		return disk_prepare();
	}

	if (count == 1) {
		results = try_with_device(*medias);
		if (results == RETURN_OK)
			return RETURN_OK;
		i = ask_insmod(SCSI_ADAPTERS);
		if (i == RETURN_BACK)
			return RETURN_BACK;
		return disk_prepare();
	}

	results = ask_from_list_comments("Please choose the DISK drive on which you copied the " DISTRIB_NAME " Distribution.", medias, medias_models, &choice);

	if (results != RETURN_OK)
		return results;

	results = try_with_device(choice);
	if (results == RETURN_OK)
		return RETURN_OK;
	i = ask_insmod(SCSI_ADAPTERS);
	if (i == RETURN_BACK)
		return RETURN_BACK;
	return disk_prepare();
}
