/*
 * Guillaume Cottenceau (gc@mandriva.com)
 *
 * Copyright 2000 Mandriva
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

enum return_type create_IMAGE_LOCATION(const char *location_full)
{
	struct stat statbuf;
	int offset = strncmp(location_full, IMAGE_LOCATION_DIR, sizeof(IMAGE_LOCATION_DIR) - 1) == 0 ? sizeof(IMAGE_LOCATION_DIR) - 1 : 0;
	char *with_arch = NULL;
	asprintf(&with_arch, "%s/%s", location_full, ARCH);

	log_message("trying %s", with_arch);

	if (stat(with_arch, &statbuf) == 0 && S_ISDIR(statbuf.st_mode))
		location_full = with_arch;

	log_message("assuming %s is a mirror tree", location_full + offset);

	unlink(IMAGE_LOCATION);
	if (symlink(location_full + offset, IMAGE_LOCATION) != 0)
		return RETURN_ERROR;

	return RETURN_OK;
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
                } else if (quantity == (size_t)-1) {
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

        return (enum return_type)ret;
}

enum return_type copy_file(const char * from, char * to, void (*callback_func)(int overall))
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

enum return_type mount_compressed_image(const char *compressed_image, const char *location_mount)
{
	if (lomount(compressed_image, location_mount, NULL, 1)) {
                stg1_error_message("Could not mount compressed loopback :(.");
                return RETURN_ERROR;
        }
	return RETURN_OK;
}

enum return_type preload_mount_compressed_fd(int compressed_fd, int image_size, const char *image_name, const char *location_mount)
{
	int ret;
	char *compressed_tmpfs = NULL;
	asprintf(&compressed_tmpfs, "/tmp/%s", image_name);
	const char *buf = "Loading program into memory...";
	if (binary_name && (!strcmp(binary_name, "stage1") || !strcmp(binary_name, "rescue-gui")))
		init_progression(buf, image_size);
	else
		init_progression_raw(buf, image_size);

	ret = save_fd(compressed_fd, compressed_tmpfs, update_progression);
	end_progression();
	if (ret != RETURN_OK)
		return (enum return_type)ret;
	
	return mount_compressed_image(compressed_tmpfs, location_mount);
}

enum return_type mount_compressed_image_may_preload(const char *image_name, const char *location_mount, int preload)
{
	char *compressed_image = NULL;
	asprintf(&compressed_image, "%s/%s", COMPRESSED_LOCATION, image_name);

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
	}
#if 0
	/* dead, we're no longer using squashfs image, but rather a compressed cpio archive in stead now */
       	else {
		/* compressed install */
		return mount_compressed_image_may_preload(COMPRESSED_NAME(""), STAGE2_LOCATION, compressed_image_preload());
	}
#else
	return RETURN_OK;
#endif
}

enum return_type load_compressed_fd(int fd, int size)
{
	/* TODO: handle cpio archive in stead of squashfs image */
	return preload_mount_compressed_fd(fd, size, COMPRESSED_NAME(""), STAGE2_LOCATION);
}

int try_mount(const char * dev, const char * location)
{
	char device_fullname[50];
	snprintf(device_fullname, sizeof(device_fullname), "/dev/%s", dev);

	if (my_mount(device_fullname, location, "ext4", 0) == -1 &&
	    my_mount(device_fullname, location, "btrfs", 0) == -1 &&
	    my_mount(device_fullname, location, "vfat", 0) == -1 &&
	    my_mount(device_fullname, location, "ntfs", 0) == -1 &&
	    my_mount(device_fullname, location, "reiserfs", 0) == -1 &&
	    my_mount(device_fullname, location, "reiser4", 0) == -1 &&
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

	my_modprobe("ide_disk", ANY_DRIVER_TYPE, NULL, 0);
	my_modprobe("sd_mod", ANY_DRIVER_TYPE, NULL, 0);

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

//	my_modprobe("ide_cd_mod", ANY_DRIVER_TYPE, NULL, 0);
	my_modprobe("sr_mod", ANY_DRIVER_TYPE, NULL, 0);

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
	my_modprobe("floppy", ANY_DRIVER_TYPE, NULL, 0);
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
                                        return strdup("/dev/fd0");
                                }
                        }
                } else {
                        log_perror("can't FDGETDRVTYP /dev/fd0");
                }
                close(fd);
        }
        log_message("seems that you don't have a regular floppy drive");
        my_modprobe("sd_mod", ANY_DRIVER_TYPE, NULL, 0);
	get_medias(FLOPPY, &names, &models, BUS_ANY);
	if (names && *names) {
		char *devnames = NULL;
                asprintf(&devnames, "/dev/%s", *names);
		return strdup(devnames);
	}
        else
                return NULL;
}
