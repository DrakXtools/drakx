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


static enum return_type third_party_get_device(char ** device)
{
	char ** medias, ** medias_models;
        char * floppy_dev;
	enum return_type results;
	char * parts[50];
	char * parts_comments[50];
        int count;

        wait_message("Looking for floppy and disk devices ...");

        count = get_disks(&medias, &medias_models);
        floppy_dev = floppy_device();
        if (strstr(floppy_dev, "/dev/") == floppy_dev) {
                floppy_dev = floppy_dev + 5;
        }

        remove_wait_message();

	if (count == 0) {
                if (floppy_dev) {
                        log_message("third party : no DISK drive found, trying with floppy");
                        *device = floppy_dev;
                        return RETURN_OK;
                } else { 
                        stg1_error_message("I can't find any floppy or disk on this system. "
                                           "No third-party kernel modules will be used.");
                        return RETURN_ERROR;
                }
	}

        if (floppy_dev) {
                medias = realloc(medias, (count + 2) * sizeof(char *));
                medias[count] = floppy_dev;
                medias[count+1] = NULL;
                medias_models = realloc(medias_models, (count + 2) * sizeof(char *));
                medias_models[count] = "Floppy device";
                medias_models[count+1] = NULL;
        }

        results = ask_from_list_comments("If you want to insert third-party kernel modules, "
                                         "please select the disk containing the modules.",
                                         medias, medias_models, device);
        if (results != RETURN_OK)
                return results;

        /* floppy is selected, don't try to list partitions */
        if (streq(*device, floppy_dev))
                return RETURN_OK;

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

        results = third_party_get_device(&choice);
	if (results != RETURN_OK)
		return;

        log_message("third party : using device %s", choice);

	if (try_mount(choice, mount_location) == -1) {
		stg1_error_message("I can't mount the selected partition.");
		return thirdparty_load_modules();
	}

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

