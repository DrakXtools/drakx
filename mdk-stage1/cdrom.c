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

#include "cdrom.h"

static enum return_type try_with_device(char *dev_name)
{
	log_message("with dev %s", dev_name);

	error_message("Should be trying with sucking device.");

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

	ptr = medias;
	while (ptr && *ptr) {
		log_message("found CDROM %s", *ptr);
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
		results = try_with_device(*medias);
		if (results == RETURN_OK)
			return RETURN_OK;
		i = ask_scsi_insmod();
		if (i == RETURN_BACK)
			return RETURN_BACK;
		return cdrom_prepare();
	}

	medias_models = get_medias(CDROM, QUERY_MODEL);

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
