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

#include "network.h"


static char * interface_select(void)
{
	char ** interfaces, ** ptr;
	char * choice;
	int i, count = 0;
	enum return_type results;

	interfaces = get_net_devices();

	ptr = interfaces;
	while (ptr && *ptr) {
		count++;
		ptr++;
	}

	if (count == 0) {
		error_message("No NET device found.");
		i = ask_insmod(NETWORK_DEVICES);
		if (i == RETURN_BACK)
			return NULL;
		return interface_select();
	}

	if (count == 1)
		return *interfaces;

	results = ask_from_list("Please choose the NET device to use for the installation.", interfaces, &choice);

	if (results != RETURN_OK)
		return NULL;

	return choice;
}

enum return_type nfs_prepare(void)
{
	char * iface = interface_select();

	if (iface == NULL)
		return RETURN_BACK;


	return RETURN_ERROR;
}

enum return_type ftp_prepare(void)
{
	return RETURN_ERROR;
}

enum return_type http_prepare(void)
{
	return RETURN_ERROR;
}
