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
#include "stage1.h"
#include "frontend.h"
#include "modules.h"
#include "probing.h"
#include "log.h"

#include "disk.h"

static enum return_type try_with_device(char *dev_name)
{

	/* I have to do the partition check here */

	return RETURN_OK;
}

enum return_type disk_prepare(void)
{
	char ** medias, ** ptr, ** medias_models;
	char * choice;
	int i, count = 0;
	enum return_type results;

	my_insmod("sd_mod");
	my_insmod("vfat");
	my_insmod("reiserfs");
	
	medias = get_medias(DISK, QUERY_NAME);

	ptr = medias;
	while (ptr && *ptr) {
		log_message("found DISK %s", *ptr);
		count++;
		ptr++;
	}

	if (count == 0) {
		error_message("No DISK drive found.");
		i = ask_scsi_insmod();
		if (i == RETURN_BACK)
			return RETURN_BACK;
		return disk_prepare();
	}

	if (count == 1) {
		results = try_with_device(*medias);
		if (results == RETURN_OK)
			return RETURN_OK;
		i = ask_scsi_insmod();
		if (i == RETURN_BACK)
			return RETURN_BACK;
		return disk_prepare();
	}

	medias_models = get_medias(DISK, QUERY_MODEL);

	results = ask_from_list_comments("Please choose the DISK drive to use for the installation.", medias, medias_models, &choice);

	if (results != RETURN_OK)
		return results;

	results = try_with_device(choice);
	if (results == RETURN_OK)
		return RETURN_OK;
	i = ask_scsi_insmod();
	if (i == RETURN_BACK)
		return RETURN_BACK;
	return disk_prepare();
}
