/* Copyright 1999 Mandrakesoft <fpons@mandrakesoft.com>
 *
 * The following file used by this one are copyrighted by RedHat and
 * are taken from kudzu :
 *   device.h
 *   serial.h
 *   serial.c
 * This file is taken from kudzu.c copyrighted by RedHat, 1999.
 *
 * This software may be freely redistributed under the terms of the GNU
 * public license.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 *
 */

#include <stdio.h>
#include <string.h>
#include <stdlib.h>

#include "serial.h"
#include "device.h"

typedef struct device *(newFunc)(struct device *);
typedef int (initFunc)();
typedef struct device *(probeFunc)(enum deviceClass, int, struct device *);

char *classStrings[] = {
	"UNSPEC", "OTHER", "NETWORK", "SCSI", "VIDEO", "AUDIO",
	"MOUSE", "MODEM", "CDROM", "TAPE", "FLOPPY", "SCANNER",
	"HD", "RAID", "PRINTER", "CAPTURE", "KEYBOARD", NULL
};

struct device *newDevice(struct device *old, struct device *new) {
    if (!old) {
	if (!new) {
	    new = malloc(sizeof(struct device));
	    memset(new,'\0',sizeof(struct device));
	}
     new->type = CLASS_UNSPEC;
    } else {
	    new->type = old->type;
	    if (old->device) new->device = strdup(old->device);
	    if (old->driver) new->driver = strdup(old->driver);
	    if (old->desc) new->desc = strdup(old->desc);
    }
    new->newDevice = newDevice;
    new->freeDevice = freeDevice;
    new->compareDevice = compareDevice;
    return new;
}

void freeDevice(struct device *dev) {
    if (!dev) {
	    printf("freeDevice(null)\n");
	    abort(); /* return; */
    }
    if (dev->device) free (dev->device);
    if (dev->driver) free (dev->driver);
    if (dev->desc) free (dev->desc);
    free (dev);
}

void writeDevice(FILE *file, struct device *dev) {}
int compareDevice(struct device *dev1, struct device *dev2) { return 0; }

int main () {
  struct device* devices = NULL;
  struct serialDevice* serialDevice = NULL;

  devices = serialProbe(CLASS_UNSPEC, 0, devices);
  while (devices) {
    serialDevice = (struct serialDevice*)devices;

    printf("CLASS=");
    if (serialDevice->type == CLASS_UNSPEC) puts("UNSPEC"); else
    if (serialDevice->type == CLASS_OTHER) puts("OTHER"); else
    if (serialDevice->type == CLASS_NETWORK) puts("NETWORK"); else
    if (serialDevice->type == CLASS_SCSI) puts("SCSI"); else
    if (serialDevice->type == CLASS_MOUSE) puts("MOUSE"); else
    if (serialDevice->type == CLASS_AUDIO) puts("AUDIO"); else
    if (serialDevice->type == CLASS_CDROM) puts("CDROM"); else
    if (serialDevice->type == CLASS_MODEM) puts("MODEM"); else
    if (serialDevice->type == CLASS_VIDEO) puts("VIDEO"); else
    if (serialDevice->type == CLASS_TAPE) puts("TAPE"); else
    if (serialDevice->type == CLASS_FLOPPY) puts("FLOPPY"); else
    if (serialDevice->type == CLASS_SCANNER) puts("SCANNER"); else
    if (serialDevice->type == CLASS_HD) puts("HD"); else
    if (serialDevice->type == CLASS_RAID) puts("RAID"); else
    if (serialDevice->type == CLASS_PRINTER) puts("PRINTER"); else
    if (serialDevice->type == CLASS_CAPTURE) puts("CAPTURE"); else
    if (serialDevice->type == CLASS_KEYBOARD) puts("KEYBOARD"); else
    if (serialDevice->type == CLASS_MONITOR) puts("MONITOR"); else
    if (serialDevice->type == CLASS_USB) puts("USB"); else
    if (serialDevice->type == CLASS_SOCKET) puts("SOCKET"); else
    if (serialDevice->type == CLASS_FIREWIRE) puts("FIREWIRE"); else
    if (serialDevice->type == CLASS_IDE) puts("IDE");
    printf("BUS=SERIAL\n");
    printf("DEVICE=/dev/%s\n", serialDevice->device);
    printf("DRIVER=%s\n", serialDevice->driver);
    if (!serialDevice->pnpdesc) printf("DESCRIPTION=%s\n", serialDevice->desc);
    if (serialDevice->pnpmfr) printf("MANUFACTURER=%s\n", serialDevice->pnpmfr);
    if (serialDevice->pnpmodel) printf("MODEL=%s\n", serialDevice->pnpmodel);
    if (serialDevice->pnpcompat) printf("COMPAT=%s\n", serialDevice->pnpcompat);
    if (serialDevice->pnpdesc) printf("DESCRIPTION=%s\n", serialDevice->pnpdesc);
    printf("\n");
    
    devices=devices->next;
  }

  return 0;
}
