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


enum return_type nfs_prepare(void)
{
	pci_probing(NETWORK_DEVICES);

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
