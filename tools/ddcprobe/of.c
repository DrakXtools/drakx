#ifdef __powerpc__

#include <sys/types.h>
#include <sys/mman.h>
#include <netinet/in.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <assert.h>
#include <limits.h>
#include <ctype.h>
#include <fcntl.h>
#include <sys/ioctl.h>
#include <linux/fb.h>
#include "vbe.h"
#include "minifind.h"

/* misnomer */
struct vbe_info *vbe_get_vbe_info()
{
	struct vbe_info *ret = NULL;
        struct fb_fix_screeninfo fix;
	unsigned char *mem;
        int rc = 0;
        int fd, i;

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

        close(fd);

        if (!rc)
        {
                // Note: if OFfb, vram info is unreliable!
		if (strcmp(fix.id, "OFfb"))
		{
	        	ret = malloc(sizeof(struct vbe_info));
			mem = strdup(fix.id);
			while(((i = strlen(mem)) > 0) && isspace(mem[i - 1])) {
				mem[i - 1] = '\0';
			}
			ret->oem_name.string = mem;
			ret->product_name.string = NULL;
			ret->vendor_name.string = NULL;
			ret->product_revision.string = NULL;
			ret->memory_size = fix.smem_len/1024;
		}
        }

	return ret;
}

int get_edid_supported()
{
	int ret = 0;
	struct findNode *list;
	struct pathNode *n;

	list = (struct findNode *) malloc(sizeof(struct findNode));
        list->result = (struct pathNode *) malloc(sizeof(struct pathNode));
        list->result->path = NULL;
        list->result->next = list->result;

        minifind("/proc/device-tree", "EDID", list);

	/* Supported */
	for (n = list->result->next; n != list->result; n = n->next)
		ret = 1;

	/* Clean up and return. */
	return ret;
}

/* Get EDID info. */
struct edid1_info *get_edid_info()
{
	unsigned char *mem;
	struct edid1_info *ret = NULL;
	struct pathNode *n;
	struct findNode *list;
	u_int16_t man;
	unsigned char edid[0x80];
	FILE* edid_file = NULL;
	char *path = NULL;

	list = (struct findNode *) malloc(sizeof(struct findNode));
        list->result = (struct pathNode *) malloc(sizeof(struct pathNode));
        list->result->path = NULL;
        list->result->next = list->result;

	minifind("/proc/device-tree", "EDID", list);

	for (n = list->result->next; n != list->result; n = n->next)
	{
		path = n->path;
		break;
	}

	if (path)
		edid_file = fopen(path, "rb" );


	if (!edid_file)
		return NULL;

	if (fread(edid, sizeof(unsigned char), 0x80, edid_file) != 0x80)
		return NULL;
  
    	fclose(edid_file);
    
	mem = malloc(sizeof(struct edid1_info));
	if(mem == NULL) {
		return NULL;
	}

	memcpy(mem, edid, 0x80);


	/* Get memory for return. */
	ret = malloc(sizeof(struct edid1_info));
	if(ret == NULL) {
		free(mem);
		return NULL;
	}

	/* Copy the buffer for return. */
	memcpy(ret, mem, sizeof(struct edid1_info));

	memcpy(&man, &ret->manufacturer_name, 2);
	man = ntohs(man);
	memcpy(&ret->manufacturer_name, &man, 2);

	free(mem);
	return ret;
}

#endif /* __powerpc__ */
