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

#include <stdlib.h>
#include <unistd.h>
#include <stdio.h>
#include <string.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <string.h>
#include "stage1.h"
#include "frontend.h"
#include "modules.h"
#include "probing.h"
#include "log.h"
#include "mount.h"
#include "lomount.h"
#include "automatic.h"

#include "disk.h"

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

static char * disk_extract_list_directory(char * direct)
{
	char ** full = list_directory(direct);
	char tmp[2000] = "";
	int i;
	for (i=0; i<5 ; i++) {
		if (!full || !*full)
			break;
		strcat(tmp, *full);
		strcat(tmp, "\n");
		full++;
	}
	return strdup(tmp);
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

	char * disk_own_mount = SLASH_LOCATION "/tmp/hdimage";
        char * loopdev = NULL;

	char * parts[50];
	char * parts_comments[50];
	struct stat statbuf;
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

	/* in testing mode, assume the partition is already mounted on SLASH_LOCATION "/tmp/hdimage" */
        if (!IS_TESTING && try_mount(choice, disk_own_mount)) {
		stg1_error_message("I can't find a valid filesystem (tried: ext2, vfat, ntfs, reiserfs).");
		return try_with_device(dev_name);
	}

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
			      "Here's a short extract of the files in the root of the partition:\n"
			      "%s", disk_extract_list_directory(disk_own_mount));
		umount(disk_own_mount);
		return try_with_device(dev_name);
	}

	unlink(IMAGE_LOCATION);

#ifndef MANDRAKE_MOVE
	if (!stat(location_full, &statbuf) && S_ISDIR(statbuf.st_mode)) {
		char **file;
		char *stage2_isos[100] = { "Use directory as a mirror tree", "-----" };
		int stage2_iso_number = 2;

		log_message("\"%s\" exists and is a directory, looking for iso files", location_full);

		for (file = list_directory(location_full); *file; file++) {
			char isofile[500], install_location[600];

			if (strstr(*file, ".iso") != *file + strlen(*file) - 4)
				/* file doesn't end in .iso, skipping */
				continue;
			
			strcpy(isofile, location_full);
			strcat(isofile, "/");
			strcat(isofile, *file);

			if (lomount(isofile, IMAGE_LOCATION, &loopdev, 0)) {
				log_message("unable to mount iso file \"%s\", skipping", isofile);
				continue;
			}

			strcpy(install_location, IMAGE_LOCATION);

			if (IS_SPECIAL_STAGE2 || ramdisk_possible())
				strcat(install_location, get_ramdisk_realname()); /* RAMDISK install */
			else
				strcat(install_location, LIVE_LOCATION); /* LIVE install */

			if (access(install_location, R_OK)) {
				log_message("ISO image \"%s\" doesn't contain stage2 installer", isofile);
			} else {
				log_message("stage2 installer found in ISO image is \"%s\"", isofile);
				stage2_isos[stage2_iso_number++] = strdup(*file);
			}

 			umount(IMAGE_LOCATION);
			del_loop(loopdev);
		}

		stage2_isos[stage2_iso_number] = NULL;

		if (stage2_iso_number > 2) {
			do {
				results = ask_from_list("Please choose the ISO image to be used to install the "
							DISTRIB_NAME " Distribution.",
							stage2_isos, file);
				if (results == RETURN_BACK) {
					umount(disk_own_mount);
					return try_with_device(dev_name);
				} else if (results == RETURN_OK) {
					if (!strcmp(*file, stage2_isos[0])) {
						/* use directory as a mirror tree */
						continue;
					} else if (!strcmp(*file, stage2_isos[1])) {
						/* the separator has been selected */
						results = RETURN_ERROR;
						continue;
					} else {
						/* use selected ISO image */
						strcat(location_full, "/");
						strcat(location_full, *file);
						log_message("installer will use ISO image \"%s\"", location_full);
					}
				}
			} while (results == RETURN_ERROR);
		} else {
			log_message("no ISO image found in \"%s\" directory", location_full);
		}
	}
#endif

	if (!stat(location_full, &statbuf) && !S_ISDIR(statbuf.st_mode)) {
		log_message("%s exists and is not a directory, assuming this is an ISO image", location_full);
		if (lomount(location_full, IMAGE_LOCATION, &loopdev, 0)) {
			stg1_error_message("Could not mount file %s as an ISO image of the " DISTRIB_NAME " Distribution.", answers_location[0]);
			umount(disk_own_mount);
			return try_with_device(dev_name);
		}
	} else
		symlink(location_full, IMAGE_LOCATION);

#ifndef MANDRAKE_MOVE
	if (IS_SPECIAL_STAGE2 || ramdisk_possible()) {
		/* RAMDISK install */
		if (access(IMAGE_LOCATION RAMDISK_LOCATION, R_OK)) {
			stg1_error_message("I can't find the " DISTRIB_NAME " Distribution in the specified directory. "
				      "(I need the subdirectory " RAMDISK_LOCATION ")\n"
				      "Here's a short extract of the files in the directory:\n"
				      "%s", disk_extract_list_directory(IMAGE_LOCATION));
			del_loop(loopdev);
			umount(disk_own_mount);
			return try_with_device(dev_name);
		}
		if (load_ramdisk() != RETURN_OK) {
			stg1_error_message("Could not load program into memory.");
			del_loop(loopdev);
			umount(disk_own_mount);
			return try_with_device(dev_name);
		}
	} else {
#endif
		/* LIVE install */
#ifdef MANDRAKE_MOVE
		if (access(IMAGE_LOCATION "/live_tree.clp", R_OK)) {
#else
		if (access(IMAGE_LOCATION LIVE_LOCATION, R_OK)) {
#endif
			stg1_error_message("I can't find the " DISTRIB_NAME " Distribution in the specified directory. "
				      "(I need the subdirectory " LIVE_LOCATION ")\n"
				      "Here's a short extract of the files in the directory:\n"
				      "%s", disk_extract_list_directory(IMAGE_LOCATION));
			del_loop(loopdev);
			umount(disk_own_mount);
			return try_with_device(dev_name);
		}
#ifndef MANDRAKE_MOVE
		char p;
		if (readlink(IMAGE_LOCATION LIVE_LOCATION "/usr/bin/runinstall2", &p, 1) != 1) {
			stg1_error_message("The " DISTRIB_NAME " Distribution seems to be copied on a Windows partition. "
				      "You need more memory to perform an installation from a Windows partition. "
				      "Another solution if to copy the " DISTRIB_NAME " Distribution on a Linux partition.");
			del_loop(loopdev);
			umount(disk_own_mount);
			return try_with_device(dev_name);
		}
		log_message("found the " DISTRIB_NAME " Installation, good news!");
	}
#endif

	if (IS_RESCUE) {
                del_loop(loopdev);
		umount(disk_own_mount);
	}

        add_to_env("METHOD", "disk");
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
		if (results == RETURN_OK)
			return RETURN_OK;
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
	if (results == RETURN_OK)
		return RETURN_OK;
	i = ask_insmod(SCSI_ADAPTERS);
	if (i == RETURN_BACK)
		return RETURN_BACK;
	return disk_prepare();
}

int
process_recovery(void)
{
	char ** medias, ** medias_models;
        int count, i;

        log_message("trying the automatic recovery of oem installs");

        count = get_disks(&medias, &medias_models);

        for (i=0; i<count; i++) {
                char * parts[50];
                char * parts_comments[50];
                char ** part, ** comment;
                log_message("examining disk %s (%s)", medias[i], medias_models[i]);

                if (list_partitions(medias[i], parts, parts_comments)) {
                        log_message("could not read partitions information, bailing out");
                        return 0;
                }

                part = parts;
                comment = parts_comments;
                while (part && *part) {
                        char * disk_own_mount = "/tmp/hdimage";
                        log_message("examining partition %s (%s)", *part, *comment);
                        if (try_mount(*part, disk_own_mount))
                                log_message("couldn't mount it");
                        else {
                                FILE *f;
                                char buf[500];
                                char location[500];
                                strcpy(location, disk_own_mount);
                                strcat(location, "/VERSION");
                                if (!(f = fopen(location, "rb")) || !fgets(buf, sizeof(buf), f)) {
                                        log_perror("could not fopen or fgets VERSION");
                                        goto examine_next_part;
                                }
                                fclose(f);
                                if (!strstr(buf, VERSION)) {
                                        log_message("mismatching VERSION contents");
                                        goto examine_next_part;
                                }
                                strcpy(location, disk_own_mount);
                                strcat(location, "/Mandrake/base");
                                if (access(location, R_OK)) {
                                        log_message("Mandrake/base is not here");
                                        goto examine_next_part;
                                }

                                log_message("going on with a recovery on disk %s partition %s", medias[i], *part);

                                symlink(disk_own_mount, IMAGE_LOCATION);
                                if (ramdisk_possible())
                                        load_ramdisk(); /* if load of ramdisk failed, try to continue in live */
                                
                                add_to_env("METHOD", "disk");
                                return 1;
                        }

                examine_next_part:
                        umount(disk_own_mount);
                        part++;
                        comment++;
                }
        }

        return 0;
}
