#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <sys/mman.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <stdarg.h>
#include "vbe.h"
#include "vesamode.h"

#ifdef HAVE_VBE
#include "int10/vbios.h"
#else
#define InitInt10(PCI_CONFIG)	0
#define FreeInt10()				/**/
#endif

#ident "$Id$"

#define SQR(x) ((x) * (x))

void log_err(char *format, ...)
{
  va_list args;
  va_start(args, format);
  vfprintf(stderr, format, args);
  va_end(args);
}

int main(void)
{
	int i, j;
	unsigned char hmin, hmax, vmin, vmax;
	struct vbe_info vbe_info_static;
	struct vbe_info *vbe_info = &vbe_info_static;
	struct vbe_edid1_info edid_static;
	struct vbe_edid1_info *edid = &edid_static;
	struct vbe_modeline *modelines;
	int pci_config_type = 0;

	/* Determine PCI configuration type */
	pci_config_type = 1;

	/* Initialize Int10 */
	if (InitInt10(pci_config_type)) return 1;

	/* Get VBE information */
	if (vbe_get_vbe_info(vbe_info) == 0) {
	  FreeInt10();
	  return 1;
	}
	printf("%dKB of video ram\n", vbe_info->memory_size / 1024);

	/* List supported standard modes */
#ifdef HAVE_VBE
	for (j = 0; j < vbe_info->modes; j++)
	  for (i = 0; known_vesa_modes[i].x; i++)
	    if (known_vesa_modes[i].number == vbe_info->mode_list[j])
	      printf("%d %d %d\n", 
		     known_vesa_modes[i].colors,
		     known_vesa_modes[i].x,
		     known_vesa_modes[i].y
		     );
#endif
	printf("\n");

	/* Get EDID information */
	if (vbe_get_edid_info(edid) == 0) {
	  FreeInt10();
	  return 0;
	}
	FreeInt10();

	if (edid->manufacturer_name.p == 0 || edid->product_code == 0) return 0;
	if (edid->version == 255 && edid->revision == 255) return 0;

	vbe_get_edid_ranges(edid, &hmin, &hmax, &vmin, &vmax);
	modelines = vbe_get_edid_modelines(edid);

	if (hmin > hmax || vmin > vmax) return 0;

	printf(hmin ? "%d-%d kHz HorizSync\n" : "\n", hmin, hmax);
	printf(vmin ? "%d-%d Hz VertRefresh\n" : "\n", vmin, vmax);

	if (edid->max_size_horizontal != 127 && edid->max_size_vertical != 127) { 
	  char manufacturer[4];
	  double size = sqrt(SQR(edid->max_size_horizontal) + 
			     SQR(edid->max_size_vertical)) / 2.54;
	  manufacturer[0] = edid->manufacturer_name.u.char1 + 'A' - 1;
	  manufacturer[1] = edid->manufacturer_name.u.char2 + 'A' - 1;
	  manufacturer[2] = edid->manufacturer_name.u.char3 + 'A' - 1;
	  manufacturer[3] = '\0';
	  printf(size ? "%3.2f inches monitor (truly %3.2f')  EISA ID=%s%04x\n" : "\n", size * 1.08, size, manufacturer, edid->product_code);
	}

	for(j=0; modelines && (modelines[j].refresh != 0); j++){
	  printf("# %dx%d, %1.1f%sHz",
		 modelines[j].width,
		 modelines[j].height,
		 modelines[j].refresh,
		 modelines[j].interlaced?"i":""
		 );
	  if(modelines[j].modeline) {
	    printf("; hfreq=%f, vfreq=%f\n%s\n",
		   modelines[j].hfreq,
		   modelines[j].vfreq,
		   modelines[j].modeline);
	  } else printf("\n");
	}
	return 0;
}
