
/* Copyright 1999 Red Hat, Inc.
 *
 * This software may be freely redistributed under the terms of the GNU
 * public license.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 *
 */


#ifndef _KUDZU_DEVICES_H_
#define _KUDZU_DEVICES_H_

#include <stdio.h>

enum deviceClass {
    /* device classes... this is somewhat ad-hoc */
	CLASS_UNSPEC, CLASS_OTHER, CLASS_NETWORK, CLASS_SCSI, CLASS_VIDEO, 
	CLASS_AUDIO, CLASS_MOUSE, CLASS_MODEM, CLASS_CDROM, CLASS_TAPE,
	CLASS_FLOPPY, CLASS_SCANNER, CLASS_HD, CLASS_RAID, CLASS_PRINTER,
	CLASS_CAPTURE, CLASS_KEYBOARD, CLASS_PCMCIA
};

enum deviceBus {
    /* 'bus' that a device is attached to... this is also ad-hoc */
    /* BUS_SBUS is sort of a misnomer - it's more or less Sun */
    /* OpenPROM probing of all various associated non-PCI buses */
    BUS_UNSPEC = 0,
    BUS_OTHER = (1 << 0),
    BUS_PCI = (1 << 1),
    BUS_SBUS = (1 << 2),
    BUS_PSAUX = (1 << 3),
    BUS_SERIAL = (1 << 4),
    BUS_PARALLEL = (1 << 5),
    BUS_SCSI = (1 << 6),
    BUS_IDE = (1 << 7),
    /* Again, misnomer */
    BUS_KEYBOARD = (1 << 8),
#ifdef _i_wanna_build_this_crap_
    BUS_ISAPNP = (1 << 9),
#endif
};

struct device {
	/* This pointer is used to make lists by the library. */
	/* Do not expect it to remain constant (or useful) across library calls. */
	struct device *next;
	/* Used for ordering, and for aliasing (modem0, modem1, etc.) */
	int index;
	enum deviceClass class;	/* type */
	enum deviceBus bus;		/* bus it's attached to */
	char * device;		/* device file associated with it */
	char * driver;		/* driver to load, if any */
	char * desc;		/* a description */
	int detached;		/* should we care if it disappears? */
	struct device *(*newDevice) (struct device *old, struct device *new);
	void (*freeDevice) (struct device *dev);
	void (*writeDevice) (FILE *file, struct device *dev);
	int (*compareDevice) (struct device *dev1, struct device *dev2);
};

struct device *newDevice(struct device *old, struct device *new);
void freeDevice(struct device *dev);
void writeDevice(FILE *file, struct device *dev);
int compareDevice(struct device *dev1, struct device *dev2);
struct device *readDevice(FILE *file);

/* Most of these aren't implemented yet...... */
/* Return everything found, even non-useful stuff */
#define PROBE_ALL       1
/* Don't do 'dangerous' probes that could do weird things (isapnp, serial) */
#define PROBE_SAFE (1<<1)
/* Stop at first device found */
#define PROBE_ONE       (1<<2)


#endif
