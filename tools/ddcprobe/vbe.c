#include <sys/types.h>
#include <sys/io.h>
#include <sys/mman.h>
#include <netinet/in.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <assert.h>
#include <limits.h>
#include <ctype.h>
#include <fcntl.h>
#include <unistd.h>
#include "vesamode.h"
#include "vbe.h"
#include "int10/vbios.h"

#define DEBUG 0
#if DEBUG
#define bug  printf
#define D(X) X
#else
#define D(X)
#endif

#ifdef __i386__
#define cpuemu 1
#else
#define cpuemu 0
#endif

/*
 * Create a 'canonical' version, i.e. no spaces at start and end.
 *
 * Note: removes chars >= 0x80 as well (due to (char *))! This
 * is currently considered a feature.
 */
static char *canon_str(char *s, int len)
{
  char *m2, *m1, *m0 = malloc(len + 1);
  int i;

  for(m1 = m0, i = 0; i < len; i++) {
    if(m1 == m0 && s[i] <= ' ') continue;
    *m1++ = s[i];
  }
  *m1 = 0;
  while(m1 > m0 && m1[-1] <= ' ') {
    *--m1 = 0;
  }

  m2 = strdup(m0);
  free(m0);

  return m2;
}

static unsigned segofs2addr(unsigned char *segofs)
{
  return segofs[0] + (segofs[1] << 8) + (segofs[2] << 4)+ (segofs[3] << 12);
}


static unsigned get_data(unsigned char *buf, unsigned buf_size, unsigned addr)
{
  unsigned bufferaddr = 0x7e00;
  unsigned len;

  *buf = 0;
  len = 0;

  if(addr >= bufferaddr && addr < bufferaddr + 0x200) {
    len = bufferaddr + 0x200 - addr;
    if(len >= buf_size) len = buf_size - 1;
    memcpy(buf, addr + (char *) 0, len);
  }
  else if(addr >= 0x0c0000 && addr < 0x100000) {
    len = 0x100000 - addr;
    if(len >= buf_size) len = buf_size - 1;
    memcpy(buf, addr + (char *) 0, len);
  }

  buf[len] = 0;

  return len;
}

#define GET_WORD(ADDR, OFS) ((ADDR)[OFS] + ((ADDR)[(OFS) + 1] << 8))

int vbe_get_vbe_info(struct vbe_info *vbe)
{
  int i, l, u;
  unsigned char v[0x200];
  unsigned char tmp[1024];
  int ax, bx, cx;

  if (vbe == NULL)
    return 0;

  /* Setup registers for the interrupt call */
  ax = 0x4f00;
  bx = 0;
  cx = 0;
  memset(v, 0, sizeof(v));
  strcpy(v, "VBE2");

  /* Get VBE block */
  i = CallInt10(&ax, &bx, &cx, v, sizeof(v), cpuemu) & 0xffff;
  if (i != 0x4f) {
    D(bug("VBE: Error (0x4f00): 0x%04x\n", i));
    return 0;
  }

  /* Parse VBE block */
  vbe->version = GET_WORD(v, 0x04);
  vbe->oem_version = GET_WORD(v, 0x14);
  vbe->memory_size = GET_WORD(v, 0x12) << 16;
  D(bug("version = %u.%u, oem version = %u.%u\n",
	vbe->version >> 8, vbe->version & 0xff, vbe->oem_version >> 8, vbe->oem_version & 0xff));
  D(bug("memory = %uk\n", vbe->memory_size >> 10));

  l = get_data(tmp, sizeof tmp, u = segofs2addr(v + 0x06));
  vbe->oem_name = canon_str(tmp, l);
  D(bug("oem name [0x%05x] = \"%s\"\n", u, vbe->oem_name));

  l = get_data(tmp, sizeof tmp, u = segofs2addr(v + 0x16));
  vbe->vendor_name = canon_str(tmp, l);
  D(bug("vendor name [0x%05x] = \"%s\"\n", u, vbe->vendor_name));

  l = get_data(tmp, sizeof tmp, u = segofs2addr(v + 0x1a));
  vbe->product_name = canon_str(tmp, l);
  D(bug("product name [0x%05x] = \"%s\"\n", u, vbe->product_name));

  l = get_data(tmp, sizeof tmp, u = segofs2addr(v + 0x1e));
  vbe->product_revision = canon_str(tmp, l);
  D(bug("product revision [0x%05x] = \"%s\"\n", u, vbe->product_revision));

  l = get_data(tmp, sizeof tmp, u = segofs2addr(v + 0x0e)) >> 1;
  for(i = vbe->modes = 0; i < l && i < sizeof vbe->mode_list / sizeof *vbe->mode_list; i++) {
    u = GET_WORD(tmp, 2 * i);
    if(u != 0xffff)
      vbe->mode_list[vbe->modes++] = u;
    else
      break;
  }
  D(bug("%u video modes\n", vbe->modes));

  return 1;
}

/* Get EDID info. */
int vbe_get_edid_info(struct vbe_edid1_info *edid)
{
  int i;
  int ax, bx, cx;

  if (edid == NULL)
    return 0;

  /* Setup registers for the interrupt call */
  ax = 0x4f15;
  bx = 1;
  cx = 0;

  /* Get EDID block */
  i = CallInt10(&ax, &bx, &cx, (unsigned char *)edid, sizeof *edid, cpuemu) & 0xffff;
  if (i != 0x4f) {
    D(bug("EDID: Error (0x4f15): 0x%04x\n", i));
    return 0;
  }

  edid->manufacturer_name.p = ntohs(edid->manufacturer_name.p);
  return 1;
}

/* Just read ranges from the EDID. */
void vbe_get_edid_ranges(struct vbe_edid1_info *edid,
			 unsigned char *hmin, unsigned char *hmax,
			 unsigned char *vmin, unsigned char *vmax)
{
	struct vbe_edid_monitor_descriptor *monitor;
	int i;

	*hmin = *hmax = *vmin = *vmax = 0;

	for(i = 0; i < 4; i++) {
		monitor = &edid->monitor_details.monitor_descriptor[i];
		if(monitor->type == vbe_edid_monitor_descriptor_range) {
			*hmin = monitor->data.range_data.horizontal_min;
			*hmax = monitor->data.range_data.horizontal_max;
			*vmin = monitor->data.range_data.vertical_min;
			*vmax = monitor->data.range_data.vertical_max;
		}
	}
}

static int compare_vbe_modelines(const void *m1, const void *m2)
{
	const struct vbe_modeline *M1 = (const struct vbe_modeline*) m1;
	const struct vbe_modeline *M2 = (const struct vbe_modeline*) m2;
	if(M1->width < M2->width) return -1;
	if(M1->width > M2->width) return 1;
	return 0;
}

struct vbe_modeline *vbe_get_edid_modelines(struct vbe_edid1_info *edid)
{
	struct vbe_modeline *ret;
	char buf[LINE_MAX];
	int modeline_count = 0, i, j;

	if (edid == NULL)
	  return NULL;

	memcpy(buf, &edid->established_timings,
	       sizeof(edid->established_timings));
	for(i = 0; i < (8 * sizeof(edid->established_timings)); i++) {
		if(buf[i / 8] & (1 << (i % 8))) {
			modeline_count++;
		}
	}

	/* Count the number of standard timings. */
	for(i = 0; i < 8; i++) {
		int x, v;
		x = edid->standard_timing[i].xresolution;
		v = edid->standard_timing[i].vfreq;
		if(((edid->standard_timing[i].xresolution & 0x01) != x) &&
		   ((edid->standard_timing[i].vfreq & 0x01) != v)) {
			modeline_count++;
		}
	}

	ret = malloc(sizeof(struct vbe_modeline) * (modeline_count + 1));
	if(ret == NULL) {
		return NULL;
	}
	memset(ret, 0, sizeof(struct vbe_modeline) * (modeline_count + 1));

	modeline_count = 0;

	/* Fill out established timings. */
	if(edid->established_timings.timing_720x400_70) {
		ret[modeline_count].width = 720;
		ret[modeline_count].height = 400;
		ret[modeline_count].refresh = 70;
		modeline_count++;
	}
	if(edid->established_timings.timing_720x400_88) {
		ret[modeline_count].width = 720;
		ret[modeline_count].height = 400;
		ret[modeline_count].refresh = 88;
		modeline_count++;
	}
	if(edid->established_timings.timing_640x480_60) {
		ret[modeline_count].width = 640;
		ret[modeline_count].height = 480;
		ret[modeline_count].refresh = 60;
		modeline_count++;
	}
	if(edid->established_timings.timing_640x480_67) {
		ret[modeline_count].width = 640;
		ret[modeline_count].height = 480;
		ret[modeline_count].refresh = 67;
		modeline_count++;
	}
	if(edid->established_timings.timing_640x480_72) {
		ret[modeline_count].width = 640;
		ret[modeline_count].height = 480;
		ret[modeline_count].refresh = 72;
		modeline_count++;
	}
	if(edid->established_timings.timing_640x480_75) {
		ret[modeline_count].width = 640;
		ret[modeline_count].height = 480;
		ret[modeline_count].refresh = 75;
		modeline_count++;
	}
	if(edid->established_timings.timing_800x600_56) {
		ret[modeline_count].width = 800;
		ret[modeline_count].height = 600;
		ret[modeline_count].refresh = 56;
		modeline_count++;
	}
	if(edid->established_timings.timing_800x600_60) {
		ret[modeline_count].width = 800;
		ret[modeline_count].height = 600;
		ret[modeline_count].refresh = 60;
		modeline_count++;
	}
	if(edid->established_timings.timing_800x600_72) {
		ret[modeline_count].width = 800;
		ret[modeline_count].height = 600;
		ret[modeline_count].refresh = 72;
		modeline_count++;
	}
	if(edid->established_timings.timing_800x600_75) {
		ret[modeline_count].width = 800;
		ret[modeline_count].height = 600;
		ret[modeline_count].refresh = 75;
		modeline_count++;
	}
	if(edid->established_timings.timing_832x624_75) {
		ret[modeline_count].width = 832;
		ret[modeline_count].height = 624;
		ret[modeline_count].refresh = 75;
		modeline_count++;
	}
	if(edid->established_timings.timing_1024x768_87i) {
		ret[modeline_count].width = 1024;
		ret[modeline_count].height = 768;
		ret[modeline_count].refresh = 87;
		ret[modeline_count].interlaced = 1;
		modeline_count++;
	}
	if(edid->established_timings.timing_1024x768_60){
		ret[modeline_count].width = 1024;
		ret[modeline_count].height = 768;
		ret[modeline_count].refresh = 60;
		modeline_count++;
	}
	if(edid->established_timings.timing_1024x768_70){
		ret[modeline_count].width = 1024;
		ret[modeline_count].height = 768;
		ret[modeline_count].refresh = 70;
		modeline_count++;
	}
	if(edid->established_timings.timing_1024x768_75){
		ret[modeline_count].width = 1024;
		ret[modeline_count].height = 768;
		ret[modeline_count].refresh = 75;
		modeline_count++;
	}
	if(edid->established_timings.timing_1280x1024_75) {
		ret[modeline_count].width = 1280;
		ret[modeline_count].height = 1024;
		ret[modeline_count].refresh = 75;
		modeline_count++;
	}

	/* Add in standard timings. */
	for(i = 0; i < 8; i++) {
		float aspect = 1;
		int x, v;
		x = edid->standard_timing[i].xresolution;
		v = edid->standard_timing[i].vfreq;
		if(((edid->standard_timing[i].xresolution & 0x01) != x) &&
		   ((edid->standard_timing[i].vfreq & 0x01) != v)) {
			switch(edid->standard_timing[i].aspect) {
				case aspect_75: aspect = 0.7500; break;
				case aspect_8: aspect = 0.8000; break;
				case aspect_5625: aspect = 0.5625; break;
				default: aspect = 1; break;
			}
			x = (edid->standard_timing[i].xresolution + 31) * 8;
			ret[modeline_count].width = x;
			ret[modeline_count].height = x * aspect;
			ret[modeline_count].refresh =
				edid->standard_timing[i].vfreq + 60;
			modeline_count++;
		}
	}

	/* Now tack on any matching modelines. */
	for(i = 0; ret[i].refresh != 0; i++) {
		struct vesa_timing_t *t = NULL;
		for(j = 0; known_vesa_timings[j].refresh != 0; j++) {
			t = &known_vesa_timings[j];
			if(ret[i].width == t->x)
			if(ret[i].height == t->y)
			if(ret[i].refresh == t->refresh) {
				snprintf(buf, sizeof(buf),
					 "ModeLine \"%dx%d\"\t%6.2f "
					 "%4d %4d %4d %4d %4d %4d %4d %4d %s %s"
					 , t->x, t->y, t->dotclock,
					 t->timings[0],
					 t->timings[0] + t->timings[1],
					 t->timings[0] + t->timings[1] +
					 t->timings[2],
					 t->timings[0] + t->timings[1] +
					 t->timings[2] + t->timings[3],
					 t->timings[4],
					 t->timings[4] + t->timings[5],
					 t->timings[4] + t->timings[5] +
					 t->timings[6],
					 t->timings[4] + t->timings[5] +
					 t->timings[6] + t->timings[7],
					 t->hsync == hsync_pos ?
					 "+hsync" : "-hsync",
					 t->vsync == vsync_pos ?
					 "+vsync" : "-vsync");
				ret[i].modeline = strdup(buf);
				ret[i].hfreq = t->hfreq;
				ret[i].vfreq = t->vfreq;
			}
		}
	}

	modeline_count = 0;
	for(i = 0; ret[i].refresh != 0; i++) {
		modeline_count++;
	}
	qsort(ret, modeline_count, sizeof(ret[0]), compare_vbe_modelines);

	return ret;
}
