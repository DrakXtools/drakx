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
#include <string.h>
#include <sys/mount.h>
#include "stage1.h"
#include "frontend.h"
#include "modules.h"
#include "probing.h"
#include "log.h"
#include "mount.h"

#include "cdrom.h"



static enum return_type try_with_device(char *dev_name)
{
	char device_fullname[50];

	strcpy(device_fullname, "/dev/");
	strcat(device_fullname, dev_name);

	if (my_mount(device_fullname, "/tmp/image", "iso9660") == -1) {
		enum return_type results;
		unset_param(MODE_AUTOMATIC); /* we are in a fallback mode */

		results = ask_yes_no("I can't access a CDROM disc in your drive.\nRetry?");
		if (results == RETURN_OK)
			return try_with_device(dev_name);
		return results;
	}	

	if (access("/tmp/image" LIVE_LOCATION, R_OK)) {
		enum return_type results;
		umount("/tmp/image");
		results = ask_yes_no("That CDROM disc does not seem to be a " DISTRIB_NAME " Installation CDROM.\nRetry with another disc?");
		if (results == RETURN_OK)
			return try_with_device(dev_name);
		return results;
	}

	log_message("found a " DISTRIB_NAME " CDROM, good news!");

	if (IS_SPECIAL_STAGE2 || ramdisk_possible())
		load_ramdisk(); /* we don't care about return code, we'll do it live if we failed */

	if (IS_RESCUE)
		umount("/tmp/image");

	method_name = strdup("cdrom");
	return RETURN_OK;
}

enum return_type cdrom_prepare(void)
{
	char ** medias, ** ptr, ** medias_models;
	char * choice;
	int i, count = 0;
	enum return_type results;

	my_insmod("ide-cd", ANY_DRIVER_TYPE, NULL);
	my_insmod("sr_mod", ANY_DRIVER_TYPE, NULL);
	
	get_medias(CDROM, &medias, &medias_models);

	ptr = medias;
	while (ptr && *ptr) {
		count++;
		ptr++;
	}

	if (count == 0) {
		error_message("No CDROM device found.");
		i = ask_insmod(SCSI_ADAPTERS);
		if (i == RETURN_BACK)
			return RETURN_BACK;
		return cdrom_prepare();
	}

	if (count == 1) {
		results = try_with_device(*medias);
		if (results == RETURN_OK)
			return RETURN_OK;
		i = ask_insmod(SCSI_ADAPTERS);
		if (i == RETURN_BACK)
			return RETURN_BACK;
		return cdrom_prepare();
	}

	if (IS_AUTOMATIC) {
		results = try_with_device(*medias);
		if (results != RETURN_OK)
			unset_param(MODE_AUTOMATIC);
		return results;
	}
	else {
		results = ask_from_list_comments("Please choose the CDROM drive to use for the installation.", medias, medias_models, &choice);
		if (results == RETURN_OK)
			results = try_with_device(choice);
		else
			return results;
	}

	if (results == RETURN_OK)
		return RETURN_OK;
	if (results == RETURN_BACK)
		return cdrom_prepare();

	i = ask_insmod(SCSI_ADAPTERS);
	if (i == RETURN_BACK)
		return RETURN_BACK;
	return cdrom_prepare();
}
