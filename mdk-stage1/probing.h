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

#ifndef _PROBING_H_
#define _PROBING_H_

enum media_type { CDROM, DISK, FLOPPY, TAPE, UNKNOWN_MEDIA };

enum driver_type { MEDIA_ADAPTERS, NETWORK_DEVICES, USB_CONTROLLERS,
    VIRTIO_DEVICES, ANY_DRIVER_TYPE };

enum media_bus { BUS_IDE, BUS_SCSI, BUS_USB, BUS_PCMCIA, BUS_ANY };

#define VIRTIO_PCI_VENDOR	0x1af4
#define VIRTIO_ID_NET		0x0001
#define VIRTIO_ID_BLOCK		0x0002
#define VIRTIO_ID_BALLOON	0x0005

void find_media(enum media_bus bus);
void get_medias(enum media_type media, char *** names, char *** models, enum media_bus bus);
char ** get_net_devices(void);
char * get_net_intf_description(char * intf_name);
void probe_that_type(enum driver_type type, enum media_bus bus);
void handle_hid(void);

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
