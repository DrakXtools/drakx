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
#include "stage1.h"
#include "frontend.h"
#include "modules.h"
#include "probing.h"
#include "log.h"
#include "mount.h"

#include "cdrom.h"


static int mount_that_cd_device(char * dev_name)
{
	char device_fullname[50];

	strcpy(device_fullname, "/dev/");
	strcat(device_fullname, dev_name);

#ifdef MANDRAKE_MOVE
	return my_mount(device_fullname, IMAGE_LOCATION, "supermount", 0);
#else
	return my_mount(device_fullname, IMAGE_LOCATION, "iso9660", 0);
#endif
}


static enum return_type try_with_device(char * dev_name, char * dev_model);

static enum return_type do_with_device(char * dev_name, char * dev_model)
{
	if (!image_has_stage2()) {
		enum return_type results;
		umount(IMAGE_LOCATION);
		results = ask_yes_no("That CDROM disc does not seem to be a " DISTRIB_NAME " Installation CDROM.\nRetry with another disc?");
		if (results == RETURN_OK)
			return try_with_device(dev_name, dev_model);
		return results;
	}

	log_message("found a " DISTRIB_NAME " CDROM, good news!");

#ifndef MANDRAKE_MOVE
	may_load_clp();

	if (IS_RESCUE)
		/* in rescue mode, we don't need the media anymore */
		umount(IMAGE_LOCATION);
#endif

        add_to_env("METHOD", "cdrom");
	return RETURN_OK;
}		

static enum return_type try_with_device(char * dev_name, char * dev_model)
{
	wait_message("Trying to access a CDROM disc (drive %s)", dev_model);

	if (mount_that_cd_device(dev_name) == -1) {
		enum return_type results;
		char msg[500];
		unset_param(MODE_AUTOMATIC); /* we are in a fallback mode */
		remove_wait_message();

		snprintf(msg, sizeof(msg), "I can't access a " DISTRIB_NAME " Installation disc in your CDROM drive (%s).\nRetry?", dev_model);
		results = ask_yes_no(msg);
		if (results == RETURN_OK)
			return try_with_device(dev_name, dev_model);
		return results;
	}	
	remove_wait_message();

	return do_with_device(dev_name, dev_model);
}

int try_automatic(char ** medias, char ** medias_models)
{
	static char * already_tried[50] = { NULL };
	char ** model = medias_models;
	char ** ptr = medias;
	int i = 0;
	while (ptr && *ptr) {
		char ** p;
		for (p = already_tried; p && *p; p++)
			if (streq(*p, *ptr)) 
				goto try_automatic_already_tried;
		*p = strdup(*ptr);
		*(p+1) = NULL;

		wait_message("Trying to access " DISTRIB_NAME " CDROM disc (drive %s)", *model);
		if (mount_that_cd_device(*ptr) != -1) {
			if (image_has_stage2()) {
				remove_wait_message();
				return i;
			}
			else
				umount(IMAGE_LOCATION);
		}
		remove_wait_message();

	try_automatic_already_tried:
		ptr++;
		model++;
		i++;
	}
	return -1;
}

enum return_type cdrom_prepare(void)
{
	char ** medias, ** ptr, ** medias_models;
	char * choice;
	int i, count = 0;
	enum return_type results;

	my_insmod("ide-cd", ANY_DRIVER_TYPE, NULL, 0);

	if (IS_AUTOMATIC) {
		get_medias(CDROM, &medias, &medias_models, BUS_IDE);
		if ((i = try_automatic(medias, medias_models)) != -1)
			return do_with_device(medias[i], medias_models[i]);
		
		my_insmod("sr_mod", ANY_DRIVER_TYPE, NULL, 0);
		get_medias(CDROM, &medias, &medias_models, BUS_SCSI);
		if ((i = try_automatic(medias, medias_models)) != -1)
			return do_with_device(medias[i], medias_models[i]);
		
		get_medias(CDROM, &medias, &medias_models, BUS_USB);
		if ((i = try_automatic(medias, medias_models)) != -1)
			return do_with_device(medias[i], medias_models[i]);

		unset_param(MODE_AUTOMATIC);
	} else
		my_insmod("sr_mod", ANY_DRIVER_TYPE, NULL, 0);


	get_medias(CDROM, &medias, &medias_models, BUS_ANY);
        ptr = medias;
        while (ptr && *ptr) {
                count++;
                ptr++;
        }

	if (count == 0) {
		stg1_error_message("No CDROM device found.");
		i = ask_insmod(SCSI_ADAPTERS);
		if (i == RETURN_BACK)
			return RETURN_BACK;
		return cdrom_prepare();
	}

	if (count == 1) {
		results = try_with_device(*medias, *medias_models);
		if (results == RETURN_OK)
			return RETURN_OK;
		i = ask_insmod(SCSI_ADAPTERS);
		if (i == RETURN_BACK)
			return RETURN_BACK;
		return cdrom_prepare();
	}

	results = ask_from_list_comments("Please choose the CDROM drive to use for the installation.", medias, medias_models, &choice);
	if (results == RETURN_OK) {
		char ** model = medias_models;
		ptr = medias;
		while (ptr && *ptr && model && *model) {
			if (!strcmp(*ptr, choice))
				break;
			ptr++;
			model++;
		}
			results = try_with_device(choice, *model);
	} else
		return results;

	if (results == RETURN_OK)
		return RETURN_OK;
	if (results == RETURN_BACK)
		return cdrom_prepare();

	i = ask_insmod(SCSI_ADAPTERS);
	if (i == RETURN_BACK)
		return RETURN_BACK;
	return cdrom_prepare();
}
