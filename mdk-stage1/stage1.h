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

#ifndef _STAGE1_H_
#define _STAGE1_H_

#include "config-stage1.h"
#include "tools.h"


/* Some global stuff */

enum return_type { RETURN_OK, RETURN_BACK, RETURN_ERROR };

extern char * method_name;

#define MODE_TESTING        (1 << 0)
#define MODE_EXPERT         (1 << 1)
#define MODE_RESCUE         (1 << 3)
#define MODE_AUTOMATIC	    (1 << 4)
#define MODE_SPECIAL_STAGE2 (1 << 8)
#define MODE_RAMDISK        (1 << 9)

#define IS_TESTING     (get_param(MODE_TESTING))
#define IS_EXPERT      (get_param(MODE_EXPERT))
#define IS_RESCUE      (get_param(MODE_RESCUE))
#define IS_AUTOMATIC   (get_param(MODE_AUTOMATIC))
#define IS_SPECIAL_STAGE2 (get_param(MODE_SPECIAL_STAGE2))
#define IS_RAMDISK     (get_param(MODE_RAMDISK))

void fatal_error(char *msg);

#endif
