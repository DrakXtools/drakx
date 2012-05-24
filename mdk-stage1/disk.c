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

#define _GNU_SOURCE         /* We want the non segfaulting my_dirname() -- See dirname(3) */
#include <string.h>
#include <stdlib.h>
#include <unistd.h>
#include <stdio.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <libgen.h>
#include "stage1.h"
#include "frontend.h"
#include "modules.h"
#include "probing.h"
#include "log.h"
#include "tools.h"
#include "utils.h"
#include "mount.h"
#include "automatic.h"
#include "directory.h"
#include "partition.h"

#include "disk.h"

static enum return_type try_automatic_with_partition(char *dev) {
	enum return_type results;
	int mounted;
	wait_message("Trying to access " DISTRIB_NAME " disk (partition %s)", dev);
	mounted = !try_mount(dev, MEDIA_LOCATION);
	remove_wait_message();
	if (mounted) {
		create_IMAGE_LOCATION(MEDIA_LOCATION);
		if (image_has_stage2()) {
			results = try_with_directory(MEDIA_LOCATION, "disk", "disk-iso");
			if (results == RETURN_OK) {
				if (!KEEP_MOUNTED)
					umount(MEDIA_LOCATION);
				return RETURN_OK;
			}
		}
	}
	if (mounted)
		umount(MEDIA_LOCATION);
	return RETURN_ERROR;
}

static enum return_type try_automatic_with_disk(char *disk, char *model) {
	char * parts[50];
	char * parts_comments[50];
	enum return_type results;
	char **dev;
	wait_message("Trying to access " DISTRIB_NAME " disk (drive %s)", model);
	if (list_partitions(disk, parts, parts_comments)) {
		stg1_error_message("Could not read partitions information.");
		return RETURN_ERROR;
	}
	remove_wait_message();
	dev = parts;
	while (dev && *dev) {
		results = try_automatic_with_partition(*dev);
		if (results == RETURN_OK) {
			return RETURN_OK;
		}
		dev++;
	}
	return RETURN_ERROR;
}

static enum return_type try_automatic(char ** medias, char ** medias_models)
{
	char ** model = medias_models;
	char ** ptr = medias;
	while (ptr && *ptr) {
		enum return_type results;
		results = try_automatic_with_disk(*ptr, *model);
		if (results == RETURN_OK)
			return RETURN_OK;
		ptr++;
		model++;
	}
	return RETURN_ERROR;
}

static enum return_type try_with_device(char *dev_name)
{
	char * questions_location[] = { "Directory or ISO images directory or ISO image", NULL };
	char * questions_location_auto[] = { "directory", NULL };
	static char ** answers_location = NULL;
	char location_full[500];

	char * parts[50];
	char * parts_comments[50];
	enum return_type results;
	char * choice;
        
        if (list_partitions(dev_name, parts, parts_comments)) {
		stg1_error_message("Could not read partitions information.");
		return RETURN_ERROR;
        }

        /* uglyness to allow auto starting with devfs */
        if (!IS_AUTOMATIC || streq((choice = get_auto_value("partition")), "")) {
                if (parts[0] == NULL) {
                        stg1_error_message("No partition found.");
                        return RETURN_ERROR;
                }

                results = ask_from_list_comments_auto("Please select the partition containing the copy of the "
						      DISTRIB_NAME " Distribution install source.",
                                                      parts, parts_comments, &choice, "partition", parts);
                if (results != RETURN_OK)
                        return results;
        }

	/* in testing mode, assume the partition is already mounted on MEDIA_LOCATION */
        if (!IS_TESTING && try_mount(choice, MEDIA_LOCATION)) {
		stg1_error_message("I can't find a valid filesystem (tried: ext2, vfat, ntfs, reiserfs). "
                                   "Make sure the partition has been cleanly unmounted.");
		return try_with_device(dev_name);
	}

 ask_dir:
	if (ask_from_entries_auto("Please enter the directory (or ISO image file) containing the "
				  DISTRIB_NAME " Distribution install source.",
				  questions_location, &answers_location, 24, questions_location_auto, NULL) != RETURN_OK) {
		umount(MEDIA_LOCATION);
		return try_with_device(dev_name);
	}

	strcpy(location_full, MEDIA_LOCATION);
	strcat(location_full, "/");
	strcat(location_full, answers_location[0]);

	if (access(location_full, R_OK)) {
		char * path = strdup(answers_location[0]);
		stg1_error_message("Directory or ISO image file could not be found on partition.\n"
			      "Here's a short extract of the files in the directory %s:\n"
			      "%s", my_dirname(path), extract_list_directory(my_dirname(location_full)));
		free(path);
		goto ask_dir;
	}

	results = try_with_directory(location_full, "disk", "disk-iso");
	if (results != RETURN_OK) {
		goto ask_dir;
	}

	if (!KEEP_MOUNTED)
		umount(MEDIA_LOCATION);

	return RETURN_OK;
}

enum return_type disk_prepare(void)
{
	char ** medias, ** medias_models;
	char * choice;
	int i;
	enum return_type results;
	static int already_probed_ide_generic = 0;

        int count = get_disks(&medias, &medias_models);

	if (IS_AUTOMATIC) {
		results = try_automatic(medias, medias_models);
		if (results != RETURN_ERROR)
			return results;
		unset_automatic();
        }

	if (count == 0) {
		if (!already_probed_ide_generic) {
			already_probed_ide_generic = 1;
			my_insmod("ide_generic", ANY_DRIVER_TYPE, NULL, 0);
			return disk_prepare();
		}
		stg1_error_message("No DISK drive found.");
		i = ask_insmod(MEDIA_ADAPTERS);
		if (i == RETURN_BACK)
			return RETURN_BACK;
		return disk_prepare();
	}

	if (count == 1) {
		results = try_with_device(*medias);
		if (results != RETURN_ERROR)
			return results;
		i = ask_insmod(MEDIA_ADAPTERS);
		if (i == RETURN_BACK)
			return RETURN_BACK;
		return disk_prepare();
	}

	results = ask_from_list_comments_auto("Please select the disk containing the copy of the "
					      DISTRIB_NAME " Distribution install source.",
					      medias, medias_models, &choice, "disk", medias);

	if (results != RETURN_OK)
		return results;

	results = try_with_device(choice);
	if (results != RETURN_ERROR)
		return results;
	i = ask_insmod(MEDIA_ADAPTERS);
	if (i == RETURN_BACK)
		return RETURN_BACK;
	return disk_prepare();
}
