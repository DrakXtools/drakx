/*
 * Guillaume Cottenceau (gc@mandrakesoft.com)
 *
 * Copyright 2000 MandrakeSoft
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


/*
 * This contains stuff related to probing:
 * (1) any (actually SCSI and NET only) devices (autoprobe for PCI)
 * (2) IDE media
 * (3) SCSI media
 * (4) ETH devices
 */


#include <stdlib.h>
#include <unistd.h>
#include <stdio.h>
#include <string.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <sys/socket.h>
#include <net/if.h>
#include <sys/ioctl.h>
#include "stage1.h"

#include "log.h"
#include "frontend.h"
#include "modules.h"
#include "pci-resource/pci-ids.h"

#include "probing.h"


enum bus_type { IDE, SCSI };

struct media_info {
	char * name;
	char * model;
	enum media_type type;
	enum bus_type bus;
};


static void warning_insmod_failed(enum insmod_return r)
{
	if (r != INSMOD_OK
	    && !(IS_AUTOMATIC && r == INSMOD_FAILED_FILE_NOT_FOUND))
		error_message("Warning, installation of driver failed. (please include msg from <Alt-F3> for bugreports)");
}

#ifndef DISABLE_NETWORK
struct net_description_elem
{
	char * intf_name;
	char * intf_description;
};
static struct net_description_elem net_descriptions[50];
static int net_descr_number = 0;
static char * intf_descr_for_discover = NULL;
static char * net_intf_too_early_name[50]; /* for modules providing more than one net intf */
static int net_intf_too_early_number = 0;
static int net_intf_too_early_ptr = 0;

void prepare_intf_descr(const char * intf_descr)
{
	intf_descr_for_discover = strdup(intf_descr);
}

void net_discovered_interface(char * intf_name)
{
	if (!intf_descr_for_discover) {
		net_intf_too_early_name[net_intf_too_early_number++] = strdup(intf_name);
		return;
	}
	if (!intf_name) {
		if (net_intf_too_early_ptr >= net_intf_too_early_number) {
			log_message("NET: was expecting another network interface (broken net module?)");
			return;
		}
		net_descriptions[net_descr_number].intf_name = net_intf_too_early_name[net_intf_too_early_ptr++];
	}
	else
		net_descriptions[net_descr_number].intf_name = strdup(intf_name);
	net_descriptions[net_descr_number].intf_description = strdup(intf_descr_for_discover);
	intf_descr_for_discover = NULL;
	net_descr_number++;
}

char * get_net_intf_description(char * intf_name)
{
	int i;
	for (i = 0; i < net_descr_number ; i++)
		if (!strcmp(net_descriptions[i].intf_name, intf_name))
			return net_descriptions[i].intf_description;
	return strdup("unknown");
}
#endif

static void probe_that_type(enum driver_type type)
{
	if (IS_EXPERT)
		ask_insmod(type);
	else { 
		/* ---- PCI probe */
		FILE * f;
		int len = 0;
		char buf[200];
		struct pci_module_map * pcidb = NULL;

		f = fopen("/proc/bus/pci/devices", "rb");
    
		if (!f) {
			log_message("PCI: could not open proc file");
			return;
		}

		switch (type) {
		case SCSI_ADAPTERS:
#ifndef DISABLE_MEDIAS
			pcidb = scsi_pci_ids;
			len   = scsi_num_ids;
#endif
			break;
		case NETWORK_DEVICES:
#ifndef DISABLE_NETWORK
			pcidb = eth_pci_ids;
			len   = eth_num_ids;
#endif
			break;
		default:
			return;
		}

		while (1) {
			int i, garb, vendor, device;

			if (!fgets(buf, sizeof(buf), f)) break;
		
			sscanf(buf, "%x %x", &garb, &vendor);
			device = vendor & 0xFFFF; /* because scanf from dietlibc does not support %4f */
			vendor = (vendor >> 16) & 0xFFFF;
 
			for (i = 0; i < len; i++) {
				if (pcidb[i].vendor == vendor && pcidb[i].device == device) {
					log_message("PCI: device %x %x is \"%s\" (%s)", vendor, device, pcidb[i].name, pcidb[i].module);
#ifndef DISABLE_MEDIAS
					if (type == SCSI_ADAPTERS) {
						/* insmod takes time, let's use the wait message */
						wait_message("Installing: %s", pcidb[i].name);
						garb = my_insmod(pcidb[i].module, SCSI_ADAPTERS, NULL);
						remove_wait_message();
						warning_insmod_failed(garb);
					}
#endif
#ifndef DISABLE_NETWORK
					if (type == NETWORK_DEVICES) {
						/* insmod is quick, let's use the info message */
						info_message("Detected network device:\n \n%s", pcidb[i].name);
						prepare_intf_descr(pcidb[i].name);
						warning_insmod_failed(my_insmod(pcidb[i].module, NETWORK_DEVICES, NULL));
						if (intf_descr_for_discover) /* for modules providing more than one net intf */
							net_discovered_interface(NULL);
					}
#endif
				}
			}
		}

		fclose(f);
	}
}


#ifndef DISABLE_MEDIAS
static struct media_info * medias = NULL;

static void find_media(void)
{
    	char b[50];
	char buf[5000];
	struct media_info tmp[50];
	int count;
        int fd;

	if (!medias)
		probe_that_type(SCSI_ADAPTERS);
	else
		free(medias); /* that does not free the strings, by the way */

	/* ----------------------------------------------- */
	log_message("looking for ide media");

    	count = 0;
    	strcpy(b, "/proc/ide/hd");
    	for (b[12] = 'a'; b[12] <= 'h'; b[12]++) {
		int i;
		char ide_disk[] = "disk";
		char ide_cdrom[] = "cdrom";
		char ide_tape[] = "tape";
		char ide_floppy[] = "floppy";
		
		/* first, test if file exists (will tell if attached medium exists) */
		b[13] = '\0';
		if (access(b, R_OK))
			continue;

		tmp[count].name = strdup("hda");
		tmp[count].name[2] = b[12];

		/* media type */
		strcpy(b + 13, "/media");
		fd = open(b, O_RDONLY);
		if (fd == -1) {
			log_message("failed to open %s for reading", b);
			continue;
		}

		i = read(fd, buf, sizeof(buf));
		if (i == -1) {
			log_message("failed to read %s", b);
			continue;
		}
		buf[i] = '\0';
		close(fd);

		if (ptr_begins_static_str(buf, ide_disk))
			tmp[count].type = DISK;
		else if (ptr_begins_static_str(buf, ide_cdrom))
			tmp[count].type = CDROM;
		else if (ptr_begins_static_str(buf, ide_tape))
			tmp[count].type = TAPE;
		else if (ptr_begins_static_str(buf, ide_floppy))
			tmp[count].type = FLOPPY;
		else
			tmp[count].type = UNKNOWN_MEDIA;

		/* media model */
		strcpy(b + 13, "/model");
		fd = open(b, O_RDONLY);
		if (fd == -1) {
			log_message("failed to open %s for reading", b);
			continue;
		}

		i = read(fd, buf, sizeof(buf));
		if (i <= 0) {
			log_message("failed to read %s", b);
			tmp[count].model = strdup("(none)");
		}
		else {
			buf[i-1] = '\0'; /* eat the \n */
			tmp[count].model = strdup(buf);
		}
		close(fd);

		log_message("IDE/%d: %s is a %s", tmp[count].type, tmp[count].name, tmp[count].model);
		tmp[count].bus = IDE;
		count++;
    	}


	/* ----------------------------------------------- */
	log_message("looking for scsi media");


	fd = open("/proc/scsi/scsi", O_RDONLY);
	if (fd != -1) {
		enum { SCSI_TOP, SCSI_HOST, SCSI_VENDOR, SCSI_TYPE } state = SCSI_TOP;
		char * start, * chptr, * next, * end;
		char scsi_disk_count = 'a';
		char scsi_cdrom_count = '0';
		char scsi_tape_count = '0';

		char scsi_no_devices[] = "Attached devices: none";
		char scsi_some_devices[] = "Attached devices: ";
		char scsi_host[] = "Host: ";
		char scsi_vendor[] = "  Vendor: ";

		int i = read(fd, &buf, sizeof(buf)-1);
		if (i < 1) {
			close(fd);
			goto end_scsi;
		}
		close(fd);
		buf[i] = '\0';

		if (ptr_begins_static_str(buf, scsi_no_devices))
			goto end_scsi;
		
		start = buf;
		while (*start) {
			char tmp_model[50];
			char tmp_name[10];

			chptr = start;
			while (*chptr != '\n') chptr++;
			*chptr = '\0';
			next = chptr + 1;
			
			switch (state) {
			case SCSI_TOP:
				if (!ptr_begins_static_str(start, scsi_some_devices))
					goto end_scsi;
				state = SCSI_HOST;
				break;

			case SCSI_HOST:
				if (!ptr_begins_static_str(start, scsi_host))
					goto end_scsi;
				state = SCSI_VENDOR;
				break;

			case SCSI_VENDOR:
				if (!ptr_begins_static_str(start, scsi_vendor))
					goto end_scsi;

				/* (1) Grab Vendor info */
				start += 10;
				end = chptr = strstr(start, "Model:");
				if (!chptr)
					goto end_scsi;

				chptr--;
				while (*chptr == ' ')
					chptr--;
				if (*chptr == ':') {
					chptr++;
					*(chptr + 1) = '\0';
					strcpy(tmp_model,"(unknown)");
				} else {
					*(chptr + 1) = '\0';
					strcpy(tmp_model, start);
				}

				/* (2) Grab Model info */
				start = end;
				start += 7;
				
				chptr = strstr(start, "Rev:");
				if (!chptr)
					goto end_scsi;
				
				chptr--;
				while (*chptr == ' ') chptr--;
				*(chptr + 1) = '\0';
				
				strcat(tmp_model, " ");
				strcat(tmp_model, start);

				tmp[count].model = strdup(tmp_model);
				
				state = SCSI_TYPE;

				break;

			case SCSI_TYPE:
				if (strncmp("  Type:", start, 7))
					goto end_scsi;
				*tmp_name = '\0';

				if (strstr(start, "Direct-Access")) {
					sprintf(tmp_name, "sd%c", scsi_disk_count++);
					tmp[count].type = DISK;
				} else if (strstr(start, "Sequential-Access")) {
					sprintf(tmp_name, "st%c", scsi_tape_count++);
					tmp[count].type = TAPE;
				} else if (strstr(start, "CD-ROM")) {
					sprintf(tmp_name, "scd%c", scsi_cdrom_count++);
					tmp[count].type = CDROM;
				}

				if (*tmp_name) {
					tmp[count].name = strdup(tmp_name);
					log_message("SCSI/%d: %s is a %s", tmp[count].type, tmp[count].name, tmp[count].model);
					tmp[count].bus = SCSI;
					count++;
				}
				
				state = SCSI_HOST;
			}
			
			start = next;
		}
		
	end_scsi:
	}

	/* ----------------------------------------------- */
	tmp[count].name = NULL;
	count++;

	medias = memdup(tmp, sizeof(struct media_info) * count);
}


/* Finds by media */
void get_medias(enum media_type media, char *** names, char *** models)
{
	struct media_info * m;
	char * tmp_names[50];
	char * tmp_models[50];
	int count;

	find_media();

	m = medias;

	count = 0;
	while (m && m->name) {
		if (m->type == media) {
			tmp_names[count] = strdup(m->name);
			tmp_models[count++] = strdup(m->model);
		}
		m++;
	}
	tmp_names[count] = NULL;
	tmp_models[count++] = NULL;

	*names = memdup(tmp_names, sizeof(char *) * count);
	*models = memdup(tmp_models, sizeof(char *) * count);
}
#endif /* DISABLE_MEDIAS */


#ifndef DISABLE_NETWORK
int net_device_available(char * device) {
	struct ifreq req;
	int s;
    
	s = socket(AF_INET, SOCK_DGRAM, 0);
	if (s < 0) {
		log_perror(device);
		return 0;
	}
	strcpy(req.ifr_name, device);
	if (ioctl(s, SIOCGIFFLAGS, &req)) {
		/* if we can't get the flags, the networking device isn't available */
		close(s);
		return 0;
	}
	close(s);
	return 1;
}


char ** get_net_devices(void)
{
	char * devices[] = {
		"eth0", "eth1", "eth2", "eth3",
		"tr0",
		"plip0", "plip1", "plip2",
		"fddi0",
		NULL
	};
	char ** ptr = devices;
	char * tmp[50];
	int i = 0;
	static int already_probed = 0;

	if (!already_probed) {
		already_probed = 1; /* cut off loop brought by: probe_that_type => my_insmod => get_net_devices */
		probe_that_type(NETWORK_DEVICES);
	}

	while (ptr && *ptr) {
		if (net_device_available(*ptr))
			tmp[i++] = strdup(*ptr);
		ptr++;
	}
	tmp[i++] = NULL;

	return memdup(tmp, sizeof(char *) * i);
}
#endif /* DISABLE_NETWORK */
