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

#ifndef _PROBING_H_
#define _PROBING_H_

enum media_type { CDROM, DISK, FLOPPY, TAPE, UNKNOWN_MEDIA };

enum bus_type { IDE, SCSI };

struct media_info {
	char * name;
	char * model;
	enum media_type type;
	enum bus_type bus;
};

enum media_query_type { QUERY_NAME, QUERY_MODEL };

enum driver_type { SCSI_ADAPTERS, NETWORK_DEVICES, ANY_DRIVER_TYPE };


void probe_that_type(enum driver_type type);
void get_medias(enum media_type media, char *** names, char *** models);
char ** get_net_devices(void);


#endif
