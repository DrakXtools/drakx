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

enum driver_type { SCSI_ADAPTERS, NETWORK_DEVICES, ANY_DRIVER_TYPE };

void get_medias(enum media_type media, char *** names, char *** models);
char ** get_net_devices(void);
void net_discovered_interface(char * intf_name);
char * get_net_intf_description(char * intf_name);
void prepare_intf_descr(const char * intf_descr);


#endif
