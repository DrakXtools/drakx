/* test for an xbox and return video ram from fb device 
 * sbenedict@mandrakesoft.com
 */

#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <ctype.h>
#include <sys/ioctl.h>
#include <linux/fb.h>
#include "vbe.h"

int box_is_xbox() {
	int is_xbox = 0;
	int result = -1;
	int fd;
	size_t rd;
	char *xbox_id = "0000\t10de02a5";
	char id[13];

	if (!(fd = open("/proc/bus/pci/devices", O_RDONLY))) {
		printf("Unable to open /proc/bus/pci/devices\n");
	}
	if (!(rd = read(fd, id, sizeof(id)))) {
		printf("Unable to read /proc/bus/pci/devices\n");
	}

	if (fd > 0)
		close(fd);

#if DEBUG	
	printf("read_id: %s\n", id);	
	printf("xbox_id: %s\n", xbox_id);	
#endif
	result = strncmp(id, xbox_id, 13);
	if (result == 0)
		is_xbox = 1;
	return is_xbox;
}

/* taken from of.c */
int get_fb_info(struct vbe_info *ret)
{
        struct fb_fix_screeninfo fix;
	unsigned char *mem;
        int rc = 0;
        int fd = -1;
	int i;

	if (ret == NULL)
		return 0;

        if (!rc && !(fd = open("/dev/fb0", O_RDONLY)))
        {
                rc = 1;
                fprintf(stderr, "Unable to open /dev/fb0. Exiting.\n");
        }

        if ((!rc) && (ioctl(fd, FBIOGET_FSCREENINFO, &fix)))
        {
                rc = 1;
                fprintf(stderr, "Framebuffer ioctl failed. Exiting.\n");
        }

	if (fd > 0)
		close(fd);

        if (!rc)
        {
                // Note: if OFfb, vram info is unreliable!
		if (strcmp(fix.id, "OFfb"))
		{
			mem = strdup(fix.id);
			while(((i = strlen(mem)) > 0) && isspace(mem[i - 1])) {
				mem[i - 1] = '\0';
			}
			ret->oem_name = strdup(mem);
			ret->product_name = NULL;
			ret->vendor_name = NULL;
			ret->product_revision = NULL;
			ret->memory_size = fix.smem_len;
		}
        }

	return !rc;
}
