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
#include "lomount.h"
#include "automatic.h"

#include "disk.h"
#include "directory.h"

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

static int list_partitions(char * dev_name, char ** parts, char ** comments)
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

static int try_mount(char * dev, char * location)
{
	char device_fullname[50];
	strcpy(device_fullname, "/dev/");
	strcat(device_fullname, dev);

	if (my_mount(device_fullname, location, "ext2", 0) == -1 &&
	    my_mount(device_fullname, location, "vfat", 0) == -1 &&
	    my_mount(device_fullname, location, "ntfs", 0) == -1 &&
	    my_mount(device_fullname, location, "reiserfs", 0) == -1) {
                return 1;
        }

        return 0;
}

static enum return_type try_with_device(char *dev_name)
{
	char * questions_location[] = { "Directory or ISO images directory or ISO image", NULL };
	char * questions_location_auto[] = { "directory", NULL };
	static char ** answers_location = NULL;
	char location_full[500];

	char * disk_own_mount = IMAGE_LOCATION_DIR "hdimage";

	char * parts[50];
	char * parts_comments[50];
	enum return_type results;
	char * choice;
        
        if (list_partitions(dev_name, parts, parts_comments)) {
		stg1_error_message("Could not read partitions information.");
		return RETURN_ERROR;
        }

        /* uglyness to allow auto starting with devfs */
        if (!IS_AUTOMATIC || streq((choice = get_auto_value("partition")), "")) {
                if (parts[0] == NULL) {
                        stg1_error_message("No partitions found.");
                        return RETURN_ERROR;
                }

                results = ask_from_list_comments_auto("Please select the partition containing the copy of the "
						      DISTRIB_NAME " Distribution install source.",
                                                      parts, parts_comments, &choice, "partition", parts);
                if (results != RETURN_OK)
                        return results;
        }

	/* in testing mode, assume the partition is already mounted on IMAGE_LOCATION_DIR "hdimage" */
        if (!IS_TESTING && try_mount(choice, disk_own_mount)) {
		stg1_error_message("I can't find a valid filesystem (tried: ext2, vfat, ntfs, reiserfs).");
		return try_with_device(dev_name);
	}

 ask_dir:
	if (ask_from_entries_auto("Please enter the directory (or ISO image file) containing the "
				  DISTRIB_NAME " Distribution install source.",
				  questions_location, &answers_location, 24, questions_location_auto, NULL) != RETURN_OK) {
		umount(disk_own_mount);
		return try_with_device(dev_name);
	}

	strcpy(location_full, disk_own_mount);
	strcat(location_full, "/");
	strcat(location_full, answers_location[0]);

	if (access(location_full, R_OK)) {
		stg1_error_message("Directory or ISO image file could not be found on partition.\n"
			      "Here's a short extract of the files in the directory %s:\n"
			      "%s", dirname(answers_location[0]), extract_list_directory(dirname(location_full)));
		goto ask_dir;
	}

	results = try_with_directory(location_full, "disk", "disk-iso");
	if (results != RETURN_OK) {
		goto ask_dir;
	}

	if (!KEEP_MOUNTED)
		umount(disk_own_mount);

	return RETURN_OK;
}

static int get_disks(char *** names, char *** models)
{
	char ** ptr;
	int count = 0;

	my_insmod("sd_mod", ANY_DRIVER_TYPE, NULL, 0);
	
	get_medias(DISK, names, models, BUS_ANY);

	ptr = *names;
	while (ptr && *ptr) {
		count++;
		ptr++;
	}

        return count;
}

enum return_type disk_prepare(void)
{
	char ** medias, ** medias_models;
	char * choice;
	int i;
	enum return_type results;

        int count = get_disks(&medias, &medias_models);

	if (count == 0) {
		stg1_error_message("No DISK drive found.");
		i = ask_insmod(SCSI_ADAPTERS);
		if (i == RETURN_BACK)
			return RETURN_BACK;
		return disk_prepare();
	}

	if (count == 1) {
		results = try_with_device(*medias);
		if (results != RETURN_ERROR)
			return results;
		i = ask_insmod(SCSI_ADAPTERS);
		if (i == RETURN_BACK)
			return RETURN_BACK;
		return disk_prepare();
	}

	results = ask_from_list_comments_auto("Please select the disk containing the copy of the "
					      DISTRIB_NAME " Distribution install source.",
					      medias, medias_models, &choice, "disk", medias);

	if (results != RETURN_OK)
		return results;

	results = try_with_device(choice);
	if (results != RETURN_ERROR)
		return results;
	i = ask_insmod(SCSI_ADAPTERS);
	if (i == RETURN_BACK)
		return RETURN_BACK;
	return disk_prepare();
}
