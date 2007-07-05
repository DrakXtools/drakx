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
#include <sys/utsname.h>

#include "stage1.h"
#include "tools.h"
#include "utils.h"
#include "log.h"
#include "modules.h"
#include "mount.h"
#include "frontend.h"
#include "partition.h"
#include "automatic.h"
#include "probing.h"

#include "thirdparty.h"

#define THIRDPARTY_MOUNT_LOCATION "/tmp/thirdparty"

#define N_PCITABLE_ENTRIES 100
static struct pcitable_entry pcitable[N_PCITABLE_ENTRIES];
static int pcitable_len = 0;

static enum return_type thirdparty_choose_device(char ** device, int probe_only)
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

	if (probe_only) {
#ifndef DISABLE_DISK
		free(disk_medias);
		free(disk_medias_models);
#endif
#ifndef DISABLE_CDROM
		free(cdrom_medias);
		free(cdrom_medias_models);
#endif
		return RETURN_OK;
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
 
	if (streq(*device, floppy_dev)) {
		/* a floppy is selected, don't try to list partitions */
		return RETURN_OK;
	}

#ifndef DISABLE_CDROM
        for (ptr = cdrom_medias; ptr < cdrom_medias + cdrom_count; ptr++) {
		if (*device == *ptr) {
			/* a cdrom is selected, don't try to list partitions */
			log_message("thirdparty: a cdrom is selected, using it (%s)", *device);
			return RETURN_OK;
		}
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
		log_message("thirdparty: found only one partition on device (%s)", parts[0]);
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
	if (try_mount(device, THIRDPARTY_MOUNT_LOCATION) != 0) {
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


static int pcitable_orderer(const void *a, const void *b)
{
	int ret;
	struct pcitable_entry *ap = (struct pcitable_entry *)a;
	struct pcitable_entry *bp = (struct pcitable_entry *)b;

	if ((ret = ap->vendor - bp->vendor) != 0)
		return ret;
	if ((ret = ap->device - bp->device) != 0)
		return ret;
	if ((ret = ap->subvendor - bp->subvendor) != 0)
		return ret;
	if ((ret = ap->subdevice - bp->subdevice) != 0)
		return ret;

	return 0;
}


static void thirdparty_load_pcitable(const char *modules_location)
{
	char pcitable_filename[100];
	FILE * f = NULL;

	sprintf(pcitable_filename, "%s/pcitable", modules_location);
	if (!(f = fopen(pcitable_filename, "rb"))) {
		log_message("third_party: no external pcitable found");
		return;
	}
	pcitable_len = 0;
	while (pcitable_len < N_PCITABLE_ENTRIES) {
		char buf[200];
		struct pcitable_entry *e;
		if (!fgets(buf, sizeof(buf), f)) break;
		e = &pcitable[pcitable_len++];
		if (sscanf(buf, "%hx\t%hx\t\"%[^ \"]\"\t\"%[^\"]\"", &e->vendor, &e->device, e->module, e->description) == 4)
			e->subvendor = e->subdevice = PCITABLE_MATCH_ALL;
		else
			sscanf(buf, "%hx\t%hx\t%x\t%x\t\"%[^ \"]\"\t\"%[^\"]\"", &e->vendor, &e->device, &e->subvendor, &e->subdevice, e->module, e->description);
	}
	fclose(f);

	/* sort pcitable by most specialised entries first */
	qsort(pcitable, pcitable_len, sizeof(pcitable[0]), pcitable_orderer);
}


static int thirdparty_is_detected(char *driver) {
	int i, j;

	for (i = 0; i < detected_devices_len ; i++) {
		/* first look for the IDs in the third-party pcitable */
		for (j = 0; j < pcitable_len ; j++) {
			if (pcitable[j].vendor == detected_devices[i].vendor &&
			    pcitable[j].device == detected_devices[i].device &&
			    !strcmp(pcitable[j].module, driver)) {
				const int subvendor = pcitable[j].subvendor;
				const int subdevice = pcitable[j].subdevice;
				if ((subvendor == PCITABLE_MATCH_ALL && subdevice == PCITABLE_MATCH_ALL) ||
					(subvendor == detected_devices[i].subvendor && subdevice == detected_devices[i].subdevice)) {
					log_message("probing: found device for module %s", driver);
					return 1;
				}
			}
		}
		/* if not found, compare with the detected driver */
		if (!strcmp(detected_devices[i].module, driver)) {
			log_message("probing: found device for module %s", driver);
			return 1;
		}
	}

	return 0;
}

static enum return_type thirdparty_autoload_modules(const char *modules_location, char ** modules_list, FILE *f, int load_detected_only)
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

		if (load_detected_only && !thirdparty_is_detected(module)) {
			log_message("third party: no device detected for module %s, skipping", module);
			continue;
		}

		log_message("third party: auto-loading module (%s) with options (%s)", module, options);
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

	return RETURN_OK;
}

static enum return_type thirdparty_try_directory(char * root_directory, int interactive) {
	char modules_location[100];
	char modules_location_release[100];
	char *list_filename;
	FILE *f_load, *f_detect;
	char **modules_list, **modules_list_release;
	struct utsname kernel_uname;

	/* look first in the specific third-party directory */
	snprintf(modules_location, sizeof(modules_location), "%s" THIRDPARTY_DIRECTORY, root_directory);
	modules_list = list_directory(modules_location);

	/* if it's empty, look in the root of selected device */
	if (!modules_list || !modules_list[0]) {
		modules_location[strlen(root_directory)] = '\0';
		modules_list = list_directory(modules_location);
		if (interactive)
			add_to_env("THIRDPARTY_DIR", "");
	} else {
		if (interactive)
			add_to_env("THIRDPARTY_DIR", THIRDPARTY_DIRECTORY);
        }

	if (uname(&kernel_uname)) {
		log_perror("uname failed");
		return RETURN_ERROR;
	}
	snprintf(modules_location_release, sizeof(modules_location_release), "%s/%s", modules_location, kernel_uname.release);
	modules_list_release = list_directory(modules_location_release);
	if (modules_list_release && modules_list_release[0]) {
		strcpy(modules_location, modules_location_release);
		modules_list = modules_list_release;
	}

	log_message("third party: using modules location %s", modules_location);

	if (!modules_list || !*modules_list) {
		log_message("third party: no modules found");
		if (interactive)
			stg1_error_message("No modules found on selected device.");
		return RETURN_ERROR;
        }

	list_filename = alloca(strlen(modules_location) + 10 /* max: "/to_detect" */ + 1);

	sprintf(list_filename, "%s/to_load", modules_location);
	f_load = fopen(list_filename, "rb");
	if (f_load) {
		thirdparty_autoload_modules(modules_location, modules_list, f_load, 0);
		fclose(f_load);
	}

	sprintf(list_filename, "%s/to_detect", modules_location);
	f_detect = fopen(list_filename, "rb");
	if (f_detect) {
		probing_detect_devices();
		thirdparty_load_pcitable(modules_location);
		thirdparty_autoload_modules(modules_location, modules_list, f_detect, 1);
		fclose(f_detect);
	}

	if (f_load || f_detect)
		return RETURN_OK;
	else if (interactive) {
		if (IS_AUTOMATIC)
			stg1_error_message("I can't find a \"to_load\" file. Please select the modules manually.");
		log_message("third party: no \"to_load\" file, prompting for modules");
		return thirdparty_prompt_modules(modules_location, modules_list);
	} else {
		return RETURN_OK;
	}
}

void thirdparty_load_media_modules(void)
{
	thirdparty_try_directory(IMAGE_LOCATION, 0);
}

void thirdparty_load_modules(void)
{
	enum return_type results;
	char * device;

	device = NULL;
	if (IS_AUTOMATIC) {
		device = get_auto_value("thirdparty");
		thirdparty_choose_device(NULL, 1); /* probe only to create devices */
		log_message("third party: trying automatic device %s", device);
		if (thirdparty_mount_device(device) != RETURN_OK)
			device = NULL;
	}

	while (!device || streq(device, "")) {
		results = thirdparty_choose_device(&device, 0);
		if (results == RETURN_BACK)
			return;
		if (thirdparty_mount_device(device) != RETURN_OK)
			device = NULL;
	}

	log_message("third party: using device %s", device);
	add_to_env("THIRDPARTY_DEVICE", device);

	results = thirdparty_try_directory(THIRDPARTY_MOUNT_LOCATION, 1);
	umount(THIRDPARTY_MOUNT_LOCATION);

	if (results != RETURN_OK)
		return thirdparty_load_modules();
}

void thirdparty_destroy(void)
{
	probing_destroy();
}
