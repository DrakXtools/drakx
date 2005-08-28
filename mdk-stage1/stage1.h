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

#ifndef _STAGE1_H_
#define _STAGE1_H_

#include "config-stage1.h"
#include "tools.h"


/* Some global stuff */

extern char * interactive_fifo;

#define MODE_TESTING        (1 << 0)
#define MODE_RESCUE         (1 << 3)
#define MODE_AUTOMATIC	    (1 << 4)
#define MODE_KEEP_MOUNTED   (1 << 5) /* for rescue */
#define MODE_DEBUGSTAGE1    (1 << 6)
#define MODE_RAMDISK        (1 << 9)
#define MODE_CHANGEDISK     (1 << 10)
#define MODE_THIRDPARTY     (1 << 11)
#define MODE_NOAUTO         (1 << 12)
#define MODE_NETAUTO        (1 << 13)
#define MODE_RECOVERY       (1 << 14)

#define IS_TESTING     (get_param(MODE_TESTING))
#define IS_RESCUE      (get_param(MODE_RESCUE))
#define IS_AUTOMATIC   (get_param(MODE_AUTOMATIC))
#define IS_DEBUGSTAGE1 (get_param(MODE_DEBUGSTAGE1))
#define IS_CHANGEDISK  (get_param(MODE_CHANGEDISK))
#define IS_THIRDPARTY  (get_param(MODE_THIRDPARTY))
#define IS_NOAUTO      (get_param(MODE_NOAUTO))
#define IS_NETAUTO     (get_param(MODE_NETAUTO))
#define IS_RECOVERY    (get_param(MODE_RECOVERY))
#define KEEP_MOUNTED   (!IS_RESCUE || get_param(MODE_KEEP_MOUNTED))

void fatal_error(char *msg) __attribute__ ((noreturn));


void stg1_error_message(char *msg, ...) __attribute__ ((format (printf, 1, 2)));
void stg1_info_message(char *msg, ...) __attribute__ ((format (printf, 1, 2)));

#endif
