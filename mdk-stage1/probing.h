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

#ifndef _PROBING_H_
#define _PROBING_H_

enum media_type { CDROM, DISK, FLOPPY, TAPE, UNKNOWN_MEDIA };

enum driver_type { SCSI_ADAPTERS, NETWORK_DEVICES, USB_CONTROLLERS, ANY_DRIVER_TYPE };

enum media_bus { BUS_IDE, BUS_SCSI, BUS_USB, BUS_PCMCIA, BUS_ANY };

void get_medias(enum media_type media, char *** names, char *** models, enum media_bus bus);
char ** get_net_devices(void);
void net_discovered_interface(char * intf_name);
char * get_net_intf_description(char * intf_name);
void prepare_intf_descr(const char * intf_descr);
void probe_that_type(enum driver_type type, enum media_bus bus);

/* Make sure the MATCH_ALL value is greater than all possible values
   for subvendor & subdevice: this simplifies the orderer */
#define PCITABLE_MATCH_ALL 0x10000

struct pcitable_entry {
	/* some bits stolen from pci-resource/pci-ids.h
	 * FIXME: split pci-ids.h into pci-ids.c and pci-ids.h so that the header can be re-used
	 */
	unsigned short	vendor;       /* PCI vendor id */
	unsigned short	device;       /* PCI device id */
	unsigned int	subvendor;    /* PCI subvendor id */
	unsigned int	subdevice;    /* PCI subdevice id */
	char      module[20];      /* module to load */
	char      description[100]; /* PCI human readable description */
};
extern struct pcitable_entry *detected_devices;
extern int detected_devices_len;
void probing_detect_devices();
void probing_destroy(void);

#endif
