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
 * (1) PCI devices
 * (2) IDE media
 * (3) SCSI media
 */


#include <stdlib.h>
#include <unistd.h>
#include <stdio.h>
#include <string.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include "log.h"
#include "frontend.h"
#include "modules.h"

#include "probing.h"


static void pci_probing(enum driver_type type)
{
	if (IS_EXPERT) {
		error_message("You should be asked if you have some SCSI.");
	} else {
		wait_message("Installing SCSI module...");
		my_insmod("advansys");
		remove_wait_message();
	}
}


static struct media_info * medias = NULL;

static void find_media(void)
{
    	char b[50];
	char buf[500];
	struct media_info tmp[50];
	int count;
        int fd;

	if (medias)
		return;

	/* ----------------------------------------------- */
	log_message("looking for ide media");

    	count = 0;
    	strcpy(b, "/proc/ide/hda");
    	for (; b[12] <= 'm'; b[12]++) {
		int i;
		
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

		if (!strncmp(buf, "disk", strlen("disk")))
			tmp[count].type = DISK;
		else if (!strncmp(buf, "cdrom", strlen("cdrom")))
			tmp[count].type = CDROM;
		else if (!strncmp(buf, "tape", strlen("tape")))
			tmp[count].type = TAPE;
		else if (!strncmp(buf, "floppy", strlen("floppy")))
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

		tmp[count].bus = IDE;
		count++;
    	}

	log_message("found %d IDE media", count);


	/* ----------------------------------------------- */
	log_message("looking for scsi media");

	pci_probing(SCSI_ADAPTERS);

	fd = open("/proc/scsi/scsi", O_RDONLY);
	if (fd != -1) {
		enum { SCSI_TOP, SCSI_HOST, SCSI_VENDOR, SCSI_TYPE } state = SCSI_TOP;
		char * start, * chptr, * next, * end;

		int i = read(fd, &buf, sizeof(buf));
		if (i < 1) {
			close(fd);
			goto end_scsi;
		}
		close(fd);
		buf[i] = '\0';

		if (!strncmp(buf, "Attached devices: none", strlen("Attached devices: none")))
			goto end_scsi;
		
		start = buf;
		while (*start) {
			char tmp_model[50];
			char tmp_name[10];
			char scsi_disk_count = 'a';
			char scsi_cdrom_count = '0';
			char scsi_tape_count = '0';

			chptr = start;
			while (*chptr != '\n') chptr++;
			*chptr = '\0';
			next = chptr + 1;
			
			switch (state) {
			case SCSI_TOP:
				if (strncmp(start, "Attached devices: ", strlen("Attached devices: ")))
					goto end_scsi;
				state = SCSI_HOST;
				break;

			case SCSI_HOST:
				if (strncmp(start, "Host: ", strlen("Host: ")))
					goto end_scsi;
				state = SCSI_VENDOR;
				break;

			case SCSI_VENDOR:
				if (strncmp(start, "  Vendor: ", strlen("  Vendor: ")))
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
				
				strcat(tmp_model, ", ");
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
					tmp[count].bus = SCSI;
					count++;
				}
				
				state = SCSI_HOST;
			}
			
			start = next;
		}
		
	end_scsi:
	}

	log_message("adding SCSI totals %d media", count);

    
	/* ----------------------------------------------- */
	tmp[count].name = NULL;
	count++;

	medias = (struct media_info *) malloc(sizeof(struct media_info) * count);
	memcpy(medias, tmp, sizeof(struct media_info) * count);
}


/* Finds by media */
char ** get_medias(enum media_type media, enum media_query_type qtype)
{
	struct media_info * m;
	char * tmp[50];
	char ** answer;
	int count;

	find_media();

	m = medias;

	count = 0;
	while (m && m->name) {
		if (m->type == media) {
			if (qtype == QUERY_NAME)
				tmp[count] = m->name;
			else
				tmp[count] = m->model;
			count++;
		}
		m++;
	}
	tmp[count] = NULL;
	count++;

	answer = (char **) malloc(sizeof(char *) * count);
	memcpy(answer, tmp, sizeof(char *) * count);

	return answer;
}
