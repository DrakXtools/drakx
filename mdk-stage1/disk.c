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
#include "stage1.h"
#include "frontend.h"
#include "modules.h"
#include "probing.h"
#include "log.h"
#include "mount.h"

#include "disk.h"


static enum return_type try_with_device(char *dev_name)
{
	char * questions_location[] = { "Directory", NULL };
	char ** answers_location;
	char device_fullname[50];
	char location_full[50];

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
			snprintf(parts_comments[i], 24, "size: %d blocks", blocks);
			i++;
		}
	}
	parts[i] = NULL;
	fclose(f);

	results = ask_from_list_comments("Please choose the partition to use for the installation.", parts, parts_comments, &choice);
	if (results != RETURN_OK)
		return results;

	strcpy(device_fullname, "/dev/");
	strcat(device_fullname, choice);
	
	if (my_mount(device_fullname, "/tmp/disk", "ext2") == -1 &&
	    my_mount(device_fullname, "/tmp/disk", "vfat") == -1 &&
	    my_mount(device_fullname, "/tmp/disk", "reiserfs") == -1) {
		error_message("I can't find a valid filesystem.");
		return try_with_device(dev_name);
	}

	results = ask_from_entries("Please enter the directory containing the " DISTRIB_NAME " Installation.",
				   questions_location, &answers_location, 24);
	if (results != RETURN_OK) {
		umount("/tmp/disk");
		return try_with_device(dev_name);
	}

	strcpy(location_full, "/tmp/disk/");
	strcat(location_full, answers_location[0]);

	if (access(location_full, R_OK)) {
		umount("/tmp/disk");
		error_message("Directory could not be found on partition.");
		return try_with_device(dev_name);
	}

	unlink("/tmp/image");
	symlink(location_full, "/tmp/image");

	if (access("/tmp/image/Mandrake/mdkinst", R_OK)) {
		umount("/tmp/disk");
		unlink("/tmp/image");
		error_message("I can't find the " DISTRIB_NAME " Installation in the specified directory.");
		return try_with_device(dev_name);
	}

	log_message("found the " DISTRIB_NAME " Installation, good news!");

	if (IS_SPECIAL_STAGE2) {
		if (load_ramdisk() != RETURN_OK) {
			error_message("Could not load program into memory");
			return try_with_device(dev_name);
		}
	}

	if (IS_RESCUE)
		umount("/tmp/image"); /* TOCHECK */

	method_name = strdup("disk");
	return RETURN_OK;
}

enum return_type disk_prepare(void)
{
	char ** medias, ** ptr, ** medias_models;
	char * choice;
	int i, count = 0;
	enum return_type results;

	my_insmod("sd_mod");
	
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

	results = ask_from_list_comments("Please choose the DISK drive to use for the installation.", medias, medias_models, &choice);

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
