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
		results = ask_yes_no("I can't access a CDROM disc in your drive.\nRetry?");
		if (results == RETURN_OK)
			return try_with_device(dev_name);
		return results;
	}	

	if (access("/tmp/image/Mandrake", R_OK)) {
		enum return_type results;
		umount("/tmp/image");
		results = ask_yes_no("That CDROM disc does not seem to be a Linux-Mandrake Installation CDROM.\nRetry with another disc?");
		if (results == RETURN_OK)
			return try_with_device(dev_name);
		return results;
	}

	log_message("found a Linux-Mandrake CDROM, good news!");
/*
	if (special_stage2 || total_memory() > 52 * 1024) loadMdkinstStage2();
	if (rescue) umount("/tmp/rhimage");
*/
	return RETURN_OK;
}

enum return_type cdrom_prepare(void)
{
	char ** medias, ** ptr, ** medias_models;
	char * choice;
	int i, count = 0;
	enum return_type results;

	my_insmod("ide-cd");
	my_insmod("sr_mod");
	my_insmod("isofs");
	
	medias = get_medias(CDROM, QUERY_NAME);
	medias_models = get_medias(CDROM, QUERY_MODEL);

	ptr = medias;
	while (ptr && *ptr) {
		log_message("have CDROM %s", *ptr);
		count++;
		ptr++;
	}

	if (count == 0) {
		error_message("No CDROM device found.");
		i = ask_scsi_insmod();
		if (i == RETURN_BACK)
			return RETURN_BACK;
		return cdrom_prepare();
	}

	if (count == 1) {
		log_message("Only one CDROM detected: %s (%s)", *medias, *medias_models);
		results = try_with_device(*medias);
		if (results == RETURN_OK)
			return RETURN_OK;
		i = ask_scsi_insmod();
		if (i == RETURN_BACK)
			return RETURN_BACK;
		return cdrom_prepare();
	}

	results = ask_from_list_comments("Please choose the CDROM drive to use for the installation.", medias, medias_models, &choice);

	if (results != RETURN_OK)
		return results;

	results = try_with_device(choice);
	if (results == RETURN_OK)
		return RETURN_OK;
	i = ask_scsi_insmod();
	if (i == RETURN_BACK)
		return RETURN_BACK;
	return cdrom_prepare();
}
