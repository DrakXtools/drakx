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

#ifndef _MOUNT_H_
#define _MOUNT_H_

#ifndef DISABLE_NETWORK
#include "nfsmount.h"
#endif

int my_mount(char *dev, char *location, char *fs, int force_rw);

#ifndef DISABLE_MEDIAS
int ensure_dev_exists(char *dev);
#endif

#endif
