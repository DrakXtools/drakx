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
#include <stdio.h>

#include "network.h"
#include "log.h"

#include "dns.h"


// needs a wrapper since gethostbyname from dietlibc doesn't support domain handling
struct hostent *mygethostbyname(const char *name)
{
	char fully_qualified[500];
	struct hostent * h;
	h = gethostbyname(name);
	if (h)
		return h;
	if (!domain)
		return NULL;
	sprintf(fully_qualified, "%s.%s", name, domain);
	h = gethostbyname(fully_qualified);
	if (!h)
		log_message("unknown host %s", name);
	return h;
}
