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


/* Some global stuff */

struct cmdline_elem
{
	char * name;
	char * value;
};

extern struct cmdline_elem params[500];


enum return_type { RETURN_OK, RETURN_BACK, RETURN_ERROR };

extern int stage1_mode;
extern char * method_name;

#define MODE_TESTING        (1 << 0)
#define MODE_EXPERT         (1 << 1)
#define MODE_TEXT           (1 << 2)
#define MODE_RESCUE         (1 << 3)
#define MODE_KICKSTART	    (1 << 4)
#define MODE_PCMCIA         (1 << 5)
#define MODE_CDROM          (1 << 6)
#define MODE_LIVE           (1 << 7)

#define IS_TESTING     ((stage1_mode) & MODE_TESTING)
#define IS_EXPERT      ((stage1_mode) & MODE_EXPERT)
#define IS_TEXT        ((stage1_mode) & MODE_TEXT)
#define IS_RESCUE      ((stage1_mode) & MODE_RESCUE)
#define IS_KICKSTART   ((stage1_mode) & MODE_KICKSTART)
#define IS_PCMCIA      ((stage1_mode) & MODE_PCMCIA)
#define IS_CDROM       ((stage1_mode) & MODE_CDROM)
#define IS_LIVE        ((stage1_mode) & MODE_LIVE)


void fatal_error(char *msg);


#endif
