/*
 * Guillaume Cottenceau (gc@mandrakesoft.com)
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
#include "automatic.h"

#include "thirdparty.h"

#define THIRDPARTY_MOUNT_LOCATION "/tmp/thirdparty"
#define THIRDPARTY_DIRECTORY "/install/thirdparty"

static enum return_type third_party_choose_device(char ** device)
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
	if (floppy_dev)
		count += 1;

	remove_wait_message();

	if (count == 0) {
		stg1_error_message("I can't find any floppy, disk or cdrom on this system. "
				   "No third-party kernel modules will be used.");
		return RETURN_BACK;
	}


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

	if (count == 1) {
		*device = medias[0];
	}  else {
		results = ask_from_list_comments("If you want to insert third-party kernel modules, "
						 "please select the disk containing the modules.",
						 medias, medias_models, device);
		if (results != RETURN_OK)
			return results;
	}
 
	/* a floppy is selected, don't try to list partitions */
	if (streq(*device, floppy_dev)) {
		return RETURN_OK;
	}

#ifndef DISABLE_CDROM
	/* a cdrom is selected, don't try to list partitions */
	if (device >= cdrom_medias) {
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
	if (results == RETURN_OK)
		return RETURN_OK;
#endif

	stg1_error_message("Sorry, no third party device can be used.");

	return RETURN_BACK;
}


static enum return_type thirdparty_mount_device(char * device)
{
        log_message("third party: trying to mount device %s", device);
	if (try_mount(device, THIRDPARTY_MOUNT_LOCATION) == -1) {
		stg1_error_message("I can't mount the selected device (%s).", device);
		return RETURN_ERROR;
	}
	return RETURN_OK;
}


static enum return_type thirdparty_prompt_modules(const char *modules_location, char ** modules_list)
{
	enum return_type results;
	char final_name[500];
	char *module_name;
	int rc;
	char * questions[] = { "Options", NULL };
	static char ** answers = NULL;

	while (1) {
		results = ask_from_list("Which driver would you like to insmod?", modules_list, &module_name);
		if (results != RETURN_OK)
			break;

		sprintf(final_name, "%s/%s", modules_location, module_name);

		results = ask_from_entries("Please enter the options:", questions, &answers, 24, NULL);
		if (results != RETURN_OK)
			continue;

		rc = insmod_local_file(final_name, answers[0]);
		if (rc) {
			log_message("\tfailed");
			stg1_error_message("Insmod failed.");
		}
	}
	return RETURN_OK;
}


static enum return_type thirdparty_autoload_modules(const char *modules_location, char ** modules_list, FILE *f)
{
	while (1) {
		char final_name[500];
		char module[500];
		char * options;
		char ** entry = modules_list;

		if (!fgets(module, sizeof(module), f)) break;
		if (module[0] == '#' || strlen(module) == 0)
			continue;

		while (module[strlen(module)-1] == '\n')
			module[strlen(module)-1] = '\0';
		options = strchr(module, ' ');
		if (options) {
			options[0] = '\0';
			options++;
		}

		log_message("third party: auto-loading module (%s) (%s)", module, options);
		while (entry && *entry) {
			if (!strncmp(*entry, module, strlen(module)) && (*entry)[strlen(module)] == '.') {
				sprintf(final_name, "%s/%s", modules_location, *entry);
				if (insmod_local_file(final_name, options)) {
					log_message("\t%s (third party media): failed", *entry);
					stg1_error_message("Insmod %s (third party media) failed.", *entry);
				}
				break;
			}
			entry++;
		}
		if (!entry || !*entry) {
			enum insmod_return ret = my_insmod(module, ANY_DRIVER_TYPE, options, 0);
			if (ret != INSMOD_OK) {
				log_message("\t%s (marfile): failed", module);
				stg1_error_message("Insmod %s (marfile) failed.", module);
			}
		}
	}
	fclose(f);

	return RETURN_OK;
}


void thirdparty_load_modules(void)
{
	enum return_type results;
	char * device, * modules_location;
	char ** modules_list;
	char toload_name[500];
	FILE * f;

	device = NULL;
	if (IS_AUTOMATIC) {
		device = get_auto_value("thirdparty");
		log_message("third party: trying automatic device %s", device);
		if (thirdparty_mount_device(device) != RETURN_OK)
			device = NULL;
	}

	while (!device || streq(device, "")) {
		results = third_party_choose_device(&device);
		if (results == RETURN_BACK)
			return;
		if (thirdparty_mount_device(device) != RETURN_OK)
			device = NULL;
	}

	log_message("third party: using device %s", device);

	/* look first in the specific third-party directory */
	modules_location = THIRDPARTY_MOUNT_LOCATION THIRDPARTY_DIRECTORY;
	modules_list = list_directory(modules_location);
	if (!modules_list || !modules_list[0]) {
		/* if it's empty, look in the root of selected device */
		modules_location = THIRDPARTY_MOUNT_LOCATION;
		modules_list = list_directory(modules_location);
	}

	log_message("third party: using modules location %s", modules_location);

	if (!modules_list || !*modules_list) {
		log_message("third party: no modules found");
		stg1_error_message("No modules found on selected device.");
		umount(THIRDPARTY_MOUNT_LOCATION);
		return thirdparty_load_modules();
	}

	sprintf(toload_name, "%s/to_load", modules_location);
	f = fopen(toload_name, "rb");
	if (f) {
		results = thirdparty_autoload_modules(modules_location, modules_list, f);
	} else {
		if (IS_AUTOMATIC)
			stg1_error_message("I can't find a \"to_load\" file. Please select the modules manually.");
		log_message("third party: no \"to_load\" file, prompting for modules");
		results = thirdparty_prompt_modules(modules_location, modules_list);
	}
	umount(THIRDPARTY_MOUNT_LOCATION);

	if (results == RETURN_OK)
		return;
	else
		return thirdparty_load_modules();
}
