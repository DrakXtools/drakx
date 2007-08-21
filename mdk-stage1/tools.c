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
#include <sys/time.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <string.h>
#include <stdio.h>
#include <dirent.h>
#include <sys/types.h>
#include <sys/mount.h>
#include <sys/poll.h>
#include <errno.h>
#include <sys/ioctl.h>
#include <linux/fd.h>
#include "stage1.h"
#include "log.h"
#include "mount.h"
#include "frontend.h"
#include "automatic.h"

#include "tools.h"
#include "utils.h"
#include "params.h"
#include "probing.h"
#include "modules.h"
#include "lomount.h"

int image_has_stage2()
{
	return access(COMPRESSED_FILE_REL(IMAGE_LOCATION "/"), R_OK) == 0 ||
	       access(IMAGE_LOCATION "/" LIVE_LOCATION_REL, R_OK) == 0;
}

int ramdisk_possible(void)
{
	if (total_memory() > (IS_RESCUE ? MEM_LIMIT_RESCUE : MEM_LIMIT_DRAKX))
		return 1;
	else {
		log_message("warning, ramdisk is not possible due to low mem!");
		return 0;
	}
}

int compressed_image_preload(void)
{
	if (total_memory() > (IS_RESCUE ? MEM_LIMIT_RESCUE_PRELOAD : MEM_LIMIT_DRAKX_PRELOAD))
		return 1;
	else {
		log_message("warning, not preloading compressed due to low mem");
		return 0;
	}
}

enum return_type save_fd(int from_fd, char * to, void (*callback_func)(int overall))
{
        FILE * f_to;
        size_t quantity __attribute__((aligned(16))), overall = 0;
        char buf[4096] __attribute__((aligned(4096)));
        int ret = RETURN_ERROR;

        if (!(f_to = fopen(to, "w"))) {
                log_perror(to);
                goto close_from;
        }

        do {
		quantity = read(from_fd, buf, sizeof(buf));
		if (quantity > 0) {
                        if (fwrite(buf, 1, quantity, f_to) != quantity) {
                                log_message("short write (%s)", strerror(errno));
                                goto cleanup;
                        }
                } else if (quantity == -1) {
			log_message("an error occured: %s", strerror(errno));
			goto cleanup;
		}

                if (callback_func) {
                        overall += quantity;
                        callback_func(overall);
                }
        } while (quantity);

        ret = RETURN_OK;

 cleanup:
        fclose(f_to);
 close_from:
        close(from_fd);

        return ret;
}

enum return_type copy_file(char * from, char * to, void (*callback_func)(int overall))
{
        int from_fd;

	log_message("copy_file: %s -> %s", from, to);

	from_fd = open(from, O_RDONLY);
	if (from_fd != -1) {
		return save_fd(from_fd, to, callback_func);
	} else {
                log_perror(from);
                return RETURN_ERROR;
        }
}

enum return_type recursiveRemove(char *file) 
{
	struct stat sb;

	if (lstat(file, &sb) != 0) {
		log_message("failed to stat %s: %d", file, errno);
		return RETURN_ERROR;
	}

	/* only descend into subdirectories if device is same as dir */
	if (S_ISDIR(sb.st_mode)) {
		char * strBuf = alloca(strlen(file) + 1024);
		DIR * dir;
		struct dirent * d;

		if (!(dir = opendir(file))) {
			log_message("error opening %s: %d", file, errno);
			return RETURN_ERROR;
		}
		while ((d = readdir(dir))) {
			if (!strcmp(d->d_name, ".") || !strcmp(d->d_name, ".."))
				continue;

			strcpy(strBuf, file);
			strcat(strBuf, "/");
			strcat(strBuf, d->d_name);

			if (recursiveRemove(strBuf) != 0) {
				closedir(dir);
				return RETURN_ERROR;
			}
		}
		closedir(dir);

		if (rmdir(file)) {
			log_message("failed to rmdir %s: %d", file, errno);
			return RETURN_ERROR;
		}
	} else {
		if (unlink(file) != 0) {
			log_message("failed to remove %s: %d", file, errno);
			return RETURN_ERROR;
		}
	}
	return RETURN_OK;
}

enum return_type recursiveRemove_if_it_exists(char *file) 
{
	struct stat sb;

	if (lstat(file, &sb) != 0) {
		/* if file doesn't exist, simply return OK */
		return RETURN_OK;
	}

	return recursiveRemove(file);
}

enum return_type mount_compressed_image(char *compressed_image,  char *location_mount)
{
	if (lomount(compressed_image, location_mount, NULL, 1)) {
                stg1_error_message("Could not mount compressed loopback :(.");
                return RETURN_ERROR;
        }
	return RETURN_OK;
}

enum return_type preload_mount_compressed_fd(int compressed_fd, int image_size, char *image_name, char *location_mount)
{
	int ret;
	char *compressed_tmpfs = asprintf_("/tmp/%s", image_name);
	char *buf = "Loading program into memory...";
	init_progression(buf, image_size);
	ret = save_fd(compressed_fd, compressed_tmpfs, update_progression);
	end_progression();
	if (ret != RETURN_OK)
		return ret;
	
	return mount_compressed_image(compressed_tmpfs, location_mount);
}

enum return_type mount_compressed_image_may_preload(char *image_name, char *location_mount, int preload)
{
	char *compressed_image = asprintf_("%s/%s", COMPRESSED_LOCATION, image_name);

	log_message("mount_compressed_may_preload: %s into %s (preload = %d)", compressed_image, location_mount, preload);

        if (access(compressed_image, R_OK) != 0) return RETURN_ERROR;

        if (preload) {
		int compressed_fd = open(compressed_image, O_RDONLY);
		if (compressed_fd != -1) {
			return preload_mount_compressed_fd(compressed_fd, file_size(compressed_image), image_name, location_mount);
		} else {
			log_perror(compressed_image);
			return RETURN_ERROR;
		}
	} else {
		return mount_compressed_image(compressed_image, location_mount);
	}
}

enum return_type may_load_compressed_image(void)
{
	if (!IS_RESCUE && access(IMAGE_LOCATION "/" LIVE_LOCATION_REL, R_OK) == 0) {
		/* LIVE install */
		return RETURN_OK;
	} else {
		/* compressed install */
		return mount_compressed_image_may_preload(COMPRESSED_NAME(""), STAGE2_LOCATION, compressed_image_preload());
	}
}

enum return_type load_compressed_fd(int fd, int size)
{
	return preload_mount_compressed_fd(fd, size, COMPRESSED_NAME(""), STAGE2_LOCATION);
}

int try_mount(char * dev, char * location)
{
	char device_fullname[50];
	snprintf(device_fullname, sizeof(device_fullname), "/dev/%s", dev);

	if (my_mount(device_fullname, location, "ext2", 0) == -1 &&
	    my_mount(device_fullname, location, "vfat", 0) == -1 &&
	    my_mount(device_fullname, location, "ntfs", 0) == -1 &&
	    my_mount(device_fullname, location, "reiserfs", 0) == -1 &&
	    my_mount(device_fullname, location, "jfs", 0) == -1 &&
	    my_mount(device_fullname, location, "xfs", 0) == -1 &&
	    my_mount(device_fullname, location, "iso9660", 0) == -1) {
                return 1;
        }

        return 0;
}

#ifndef DISABLE_DISK
int get_disks(char *** names, char *** models)
{
	char ** ptr;
	int count = 0;

	my_insmod("ide_disk", ANY_DRIVER_TYPE, NULL, 0);
	my_insmod("sd_mod", ANY_DRIVER_TYPE, NULL, 0);

	get_medias(DISK, names, models, BUS_ANY);

	ptr = *names;
	while (ptr && *ptr) {
		count++;
		ptr++;
	}

        return count;
}
#endif

#ifndef DISABLE_CDROM
int get_cdroms(char *** names, char *** models)
{
	char ** ptr;
	int count = 0;

	my_insmod("ide_cd", ANY_DRIVER_TYPE, NULL, 0);
	my_insmod("sr_mod", ANY_DRIVER_TYPE, NULL, 0);

	get_medias(CDROM, names, models, BUS_ANY);

	ptr = *names;
	while (ptr && *ptr) {
		count++;
		ptr++;
	}

	return count;
}
#endif

char * floppy_device(void)
{
        char ** names, ** models;
        int fd;
	my_insmod("floppy", ANY_DRIVER_TYPE, NULL, 0);
        fd = open("/dev/fd0", O_RDONLY|O_NONBLOCK);
        if (fd != -1) {
                char drivtyp[17];
                if (!ioctl(fd, FDGETDRVTYP, (void *)drivtyp)) {
                        struct floppy_drive_struct ds;
                        log_message("/dev/fd0 type: %s", drivtyp);
                        if (!ioctl(fd, FDPOLLDRVSTAT, &ds)) {
                                log_message("\ttrack: %d", ds.track);
                                if (ds.track >= 0) {
                                        close(fd);
                                        return "/dev/fd0";
                                }
                        }
                } else {
                        log_perror("can't FDGETDRVTYP /dev/fd0");
                }
                close(fd);
        }
        log_message("seems that you don't have a regular floppy drive");
        my_insmod("sd_mod", ANY_DRIVER_TYPE, NULL, 0);
	get_medias(FLOPPY, &names, &models, BUS_ANY);
	if (names && *names)
                return asprintf_("/dev/%s", *names);
        else
                return "/dev/fd0";
}
