/* Copyright 1999 MandrakeSoft <fpons@mandrakesoft.com>
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
	    new->class = CLASS_UNSPEC;
    } else {
	    new->class = old->class;
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

    printf("CLASS=%s\n", classStrings[serialDevice->class]);
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
