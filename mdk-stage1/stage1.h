/*
 * Guillaume Cottenceau (gc@mandriva.com)
 *
 * Copyright 2000 Mandriva
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
#include "params.h"


/* Some global stuff */

extern char * interactive_fifo;

enum mode {
	MODE_TESTING	=	(1 << 0),
	MODE_RESCUE	=	(1 << 1),
	MODE_AUTOMATIC	=	(1 << 2),
	MODE_KEEP_MOUNTED =	(1 << 3), /* for rescue */
	MODE_DEBUGSTAGE1 =	(1 << 4),
	MODE_RAMDISK =		(1 << 5),
	MODE_CHANGEDISK =	(1 << 6),
	MODE_THIRDPARTY =	(1 << 7),
	MODE_NOAUTO	=	(1 << 8),
	MODE_NETAUTO	=	(1 << 9),
	MODE_RECOVERY	=	(1 << 10),
	MODE_KEEPSHELL	=	(1 << 11),
	MODE_NETTEST	=	(1 << 12)
};

#define IS_TESTING     (get_param(MODE_TESTING))
#define IS_RESCUE      (get_param(MODE_RESCUE))
#define IS_AUTOMATIC   (get_param(MODE_AUTOMATIC))
#define IS_DEBUGSTAGE1 (get_param(MODE_DEBUGSTAGE1))
#define IS_CHANGEDISK  (get_param(MODE_CHANGEDISK))
#define IS_THIRDPARTY  (get_param(MODE_THIRDPARTY))
#define IS_NOAUTO      (get_param(MODE_NOAUTO))
#define IS_NETAUTO     (get_param(MODE_NETAUTO))
#define IS_RECOVERY    (get_param(MODE_RECOVERY))
#define	IS_KEEPSHELL   (get_param(MODE_KEEPSHELL))
#define	IS_NETTEST     (get_param(MODE_NETTEST))
#define KEEP_MOUNTED   (!IS_RESCUE || get_param(MODE_KEEP_MOUNTED))

void fatal_error(char *msg) __attribute__ ((noreturn));


void stg1_error_message(char *msg, ...) __attribute__ ((format (printf, 1, 2)));
void stg1_info_message(char *msg, ...) __attribute__ ((format (printf, 1, 2)));

#endif
