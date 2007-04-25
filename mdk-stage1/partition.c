/*
 * Guillaume Cottenceau (gc@mandrakesoft.com)
 *
 * Copyright 2000 Mandrakesoft
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

#include <stdlib.h>
#include <unistd.h>
#include <stdio.h>
#include <string.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <string.h>
#include <libgen.h>
#include "stage1.h"
#include "frontend.h"
#include "modules.h"
#include "probing.h"
#include "log.h"
#include "mount.h"
#include "automatic.h"

#include "disk.h"
#include "partition.h"

struct partition_detection_anchor {
	off_t offset;
	const char * anchor;
};

static int seek_and_compare(int fd, struct partition_detection_anchor anch)
{
	char buf[500];
	size_t count;
	if (lseek(fd, anch.offset, SEEK_SET) == (off_t)-1) {
		log_perror("seek failed");
		return -1;
	}
	count = read(fd, buf, strlen(anch.anchor));
	if (count != strlen(anch.anchor)) {
		log_perror("read failed");
		return -1;
	}
	buf[count] = '\0';
	if (strcmp(anch.anchor, buf))
		return 1;
	return 0;
}

static const char * detect_partition_type(char * dev)
{
	struct partition_detection_info {
		const char * name;
		struct partition_detection_anchor anchor0;
		struct partition_detection_anchor anchor1;
		struct partition_detection_anchor anchor2;
	};
	struct partition_detection_info partitions_signatures[] = { 
		{ "Linux Swap", { 4086, "SWAP-SPACE" }, { 0, NULL }, { 0, NULL } },
		{ "Linux Swap", { 4086, "SWAPSPACE2" }, { 0, NULL }, { 0, NULL } },
		{ "Ext2", { 0x438, "\x53\xEF" }, { 0, NULL }, { 0, NULL } },
		{ "ReiserFS", { 0x10034, "ReIsErFs" }, { 0, NULL }, { 0, NULL } },
		{ "ReiserFS", { 0x10034, "ReIsEr2Fs" }, { 0, NULL }, { 0, NULL } },
		{ "XFS", { 0, "XFSB" }, { 0x200, "XAGF" }, { 0x400, "XAGI" } },
		{ "JFS", { 0x8000, "JFS1" }, { 0, NULL }, { 0, NULL } },
		{ "NTFS", { 0x1FE, "\x55\xAA" }, { 0x3, "NTFS" }, { 0, NULL } },
		{ "FAT32", { 0x1FE, "\x55\xAA" }, { 0x52, "FAT32" }, { 0, NULL } },
		{ "FAT", { 0x1FE, "\x55\xAA" }, { 0x36, "FAT" }, { 0, NULL } },
		{ "Linux LVM", { 0, "HM\1\0" }, { 0, NULL }, { 0, NULL } }
	};
	int partitions_signatures_nb = sizeof(partitions_signatures) / sizeof(struct partition_detection_info);
	int i;
	int fd;
        const char *part_type = NULL;

	char device_fullname[50];
	strcpy(device_fullname, "/dev/");
	strcat(device_fullname, dev);

	if (ensure_dev_exists(device_fullname))
		return NULL;
	log_message("guessing type of %s", device_fullname);

	if ((fd = open(device_fullname, O_RDONLY, 0)) < 0) {
		log_perror("open");
		return NULL;
	}
	
	for (i=0; i<partitions_signatures_nb; i++) {
		int results = seek_and_compare(fd, partitions_signatures[i].anchor0);
		if (results == -1)
			goto detect_partition_type_end;
		if (results == 1)
			continue;
		if (!partitions_signatures[i].anchor1.anchor)
			goto detect_partition_found_it;

		results = seek_and_compare(fd, partitions_signatures[i].anchor1);
		if (results == -1)
			goto detect_partition_type_end;
		if (results == 1)
			continue;
		if (!partitions_signatures[i].anchor2.anchor)
			goto detect_partition_found_it;

		results = seek_and_compare(fd, partitions_signatures[i].anchor2);
		if (results == -1)
			goto detect_partition_type_end;
		if (results == 1)
			continue;

	detect_partition_found_it:
		part_type = partitions_signatures[i].name;
                break;
	}

 detect_partition_type_end:
	close(fd);
	return part_type;
}

int list_partitions(char * dev_name, char ** parts, char ** comments)
{
	int major, minor, blocks;
	char name[100];
	FILE * f;
	int i = 0;
	char buf[512];

	if (!(f = fopen("/proc/partitions", "rb")) || !fgets(buf, sizeof(buf), f) || !fgets(buf, sizeof(buf), f)) {
		log_perror(dev_name);
                return 1;
	}

	while (fgets(buf, sizeof(buf), f)) {
		memset(name, 0, sizeof(name));
		sscanf(buf, " %d %d %d %s", &major, &minor, &blocks, name);
		if ((strstr(name, dev_name) == name) && (blocks > 1) && (name[strlen(dev_name)] != '\0')) {
			const char * partition_type = detect_partition_type(name);
			parts[i] = strdup(name);
			comments[i] = (char *) malloc(sizeof(char) * 100);
			sprintf(comments[i], "size: %d Mbytes", blocks >> 10);
			if (partition_type) {
				strcat(comments[i], ", type: ");
				strcat(comments[i], partition_type);
			}
			i++;
		}
	}
	parts[i] = NULL;
	fclose(f);

        return 0;
}
