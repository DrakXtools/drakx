#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include "vbe.h"
#include "vesamode.h"
#ident "$Id$"

#define SQR(x) ((x) * (x))

int main(int argc, char **argv)
{
	int i, j;
	u_int16_t *mode_list;
	unsigned char hmin, hmax, vmin, vmax;
	struct vbe_info *vbe_info;
	struct vbe_edid1_info *edid;
	struct vbe_modeline *modelines;
	

	if ((vbe_info = vbe_get_vbe_info()) == NULL) return 1;

	printf("%dKB of video ram\n", vbe_info->memory_size * 64);

	/* List supported standard modes. */
	for (mode_list = vbe_info->mode_list.list; *mode_list != 0xffff; mode_list++)
	  for (i = 0; known_vesa_modes[i].x; i++)
	    if (known_vesa_modes[i].number == *mode_list)
	      printf("%d %d %d\n", 
		     known_vesa_modes[i].colors,
		     known_vesa_modes[i].x,
		     known_vesa_modes[i].y
		     );
	printf("\n");

	if ((edid = vbe_get_edid_info()) == NULL) return 0;
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
	  manufacturer[0] = edid->manufacturer_name.char1 + 'A' - 1;
	  manufacturer[1] = edid->manufacturer_name.char2 + 'A' - 1;
	  manufacturer[2] = edid->manufacturer_name.char3 + 'A' - 1;
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
