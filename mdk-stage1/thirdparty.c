/*
 * Olivier Blin (oblin@mandrakesoft.com)
 *
 * Copyright 2005 Mandrakesoft
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
#include <stdio.h>
#include <string.h>
#include <sys/mount.h>

#include "stage1.h"
#include "log.h"
#include "insmod.h"
#include "modules.h"
#include "mount.h"
#include "frontend.h"
#include "partition.h"

#include "thirdparty.h"


static enum return_type third_party_choose_device(char ** device, char *mount_location)
{
	char ** medias, ** medias_models;
	char ** ptr, ** ptr_models;
#ifndef DISABLE_DISK
	char ** disk_medias, ** disk_medias_models;
	int disk_count;
	char * parts[50];
	char * parts_comments[50];
#endif
#ifndef DISABLE_CDROM
	char ** cdrom_medias, ** cdrom_medias_models;
	int cdrom_count;
#endif
	char * floppy_dev;
	enum return_type results;
	int count = 0;

	wait_message("Looking for floppy, disk and cdrom devices ...");

#ifndef DISABLE_DISK
	disk_count = get_disks(&disk_medias, &disk_medias_models);
	count += disk_count;
#endif
#ifndef DISABLE_CDROM
        cdrom_count = get_cdroms(&cdrom_medias, &cdrom_medias_models);
        count += cdrom_count;
#endif

	floppy_dev = floppy_device();
	if (strstr(floppy_dev, "/dev/") == floppy_dev) {
		floppy_dev = floppy_dev + 5;
	}

	remove_wait_message();

	if (count == 0) {
		if (floppy_dev) {
			log_message("third party : no disk or cdrom drive found, trying with floppy");
			*device = floppy_dev;
			return RETURN_OK;
		} else { 
			stg1_error_message("I can't find any floppy, disk or cdrom on this system. "
					   "No third-party kernel modules will be used.");
			return RETURN_ERROR;
		}
	}

	if (floppy_dev)
		count += 1;

	ptr = medias = malloc((count + 1) * sizeof(char *));
	ptr_models =medias_models = malloc((count + 1) * sizeof(char *));
#ifndef DISABLE_DISK
	memcpy(ptr, disk_medias, disk_count * sizeof(char *));
	memcpy(ptr_models, disk_medias_models, disk_count * sizeof(char *));
	free(disk_medias);
	free(disk_medias_models);
	ptr += disk_count;
	ptr_models += disk_count;
#endif
#ifndef DISABLE_CDROM
	memcpy(ptr, cdrom_medias, cdrom_count * sizeof(char *));
	memcpy(ptr_models, cdrom_medias_models, cdrom_count * sizeof(char *));
	free(cdrom_medias);
	free(cdrom_medias_models);
	cdrom_medias = ptr; /* used later to know if a cdrom is selected */
	ptr += cdrom_count;
	ptr_models += cdrom_count;
#endif
	if (floppy_dev) {
		ptr[0] = floppy_dev;
		ptr_models[0] = "Floppy device";
		ptr++;
		ptr_models++;
 	}
	ptr[0] = NULL;
	ptr_models[0] = NULL;

	results = ask_from_list_comments("If you want to insert third-party kernel modules, "
					 "please select the disk containing the modules.",
					 medias, medias_models, device);
	if (results != RETURN_OK)
		return results;

	/* a floppy is selected, don't try to list partitions */
	if (streq(*device, floppy_dev)) {
		if (try_mount(floppy_dev, mount_location) == -1) {
			stg1_error_message("I can't mount the selected floppy.");
			return RETURN_ERROR;
		}
		return RETURN_OK;
	}

#ifndef DISABLE_CDROM
	/* a cdrom is selected, mount it as iso9660 */
	if (device >= cdrom_medias) {
		char device_fullname[50];
		strcpy(device_fullname, "/dev/");
		strcat(device_fullname, *device);
		if (my_mount(device_fullname, mount_location, "iso9660", 0)) {
			stg1_error_message("I can't mount the selected cdrom.");
			return RETURN_ERROR;
		}
		return RETURN_OK;
	}
#endif

#ifndef DISABLE_DISK
	/* a disk or usb key is selected */
	if (list_partitions(*device, parts, parts_comments)) {
		stg1_error_message("Could not read partitions information.");
		return RETURN_ERROR;
	}

	if (parts[0] == NULL) {
		stg1_error_message("No partition found.");
		return RETURN_ERROR;
	}

	/* only one partition has been discovered, don't ask which one to use */
	if (parts[1] == NULL) {
		*device = parts[0];
		return RETURN_OK;
        }

	results = ask_from_list_comments("Please select the partition containing "
					 "the third party modules.",
					 parts, parts_comments, device);
	if (results == RETURN_OK) {
		if (try_mount(*device, mount_location) == -1) {
			stg1_error_message("I can't mount the selected partition.");
			return RETURN_ERROR;
		}
		return RETURN_OK;
	}
#endif

	return results;
}

void thirdparty_load_modules(void)
{
	enum return_type results;
	char * mount_location = "/tmp/thirdparty";
	char ** modules;
	char final_name[500];
	char * choice;
	int rc;
	char * questions[] = { "Options", NULL };
	static char ** answers = NULL;

	do {
		results = third_party_choose_device(&choice, mount_location);
		if (results == RETURN_BACK)
			return;
	} while (results == RETURN_ERROR);

        log_message("third party : using device %s", choice);

	modules = list_directory(mount_location);

	if (!modules || !*modules) {
		stg1_error_message("No modules found on disk.");
		umount(mount_location);
		return thirdparty_load_modules();
	}

	results = ask_from_list("Which driver would you like to insmod?", modules, &choice);
	if (results != RETURN_OK) {
		umount(mount_location);
		return thirdparty_load_modules();
	}

	sprintf(final_name, "%s/%s", mount_location, choice);

	results = ask_from_entries("Please enter the options:", questions, &answers, 24, NULL);
	if (results != RETURN_OK) {
		umount(mount_location);
		return thirdparty_load_modules();
	}

	rc = insmod_local_file(final_name, answers[0]);
	umount(mount_location);

	if (rc) {
		log_message("\tfailed");
		stg1_error_message("Insmod failed.");
	}

	return thirdparty_load_modules();
}

