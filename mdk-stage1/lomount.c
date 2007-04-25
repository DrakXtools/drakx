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

/* This code comes from util-linux-2.10n (mount/lomount.c)
 * (this is a simplified version of this code)
 */

#include <sys/types.h>
#include <sys/mount.h>
#include <sys/ioctl.h>
#include <sys/mount.h>
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

#include "stage1.h"
#include "frontend.h"
#include "log.h"
#include "mount.h"
#include "modules.h"

#include "lomount.h"


#define LO_NAME_SIZE	64
#define LO_KEY_SIZE	32

struct loop_info
{
	int		lo_number;	/* ioctl r/o */
	dev_t		lo_device; 	/* ioctl r/o */
	unsigned long	lo_inode; 	/* ioctl r/o */
	dev_t		lo_rdevice; 	/* ioctl r/o */
	int		lo_offset;
	int		lo_encrypt_type;
	int		lo_encrypt_key_size; 	/* ioctl w/o */
	int		lo_flags;	/* ioctl r/o */
	char		lo_name[LO_NAME_SIZE];
	unsigned char	lo_encrypt_key[LO_KEY_SIZE]; /* ioctl w/o */
	unsigned long	lo_init[2];
	char		reserved[4];
};

#define LOOP_SET_FD	0x4C00
#define LOOP_CLR_FD	0x4C01
#define LOOP_SET_STATUS	0x4C02
#define LOOP_GET_STATUS	0x4C03

int
set_loop (const char *device, const char *file)
{
	struct loop_info loopinfo;
	int fd, ffd, mode;

	mode = O_RDONLY;

	if ((ffd = open (file, mode)) < 0)
		return 1;
  
	if ((fd = open (device, mode)) < 0) {
		close(ffd);
		return 1;
	}

	memset(&loopinfo, 0, sizeof (loopinfo));
	strncpy(loopinfo.lo_name, file, LO_NAME_SIZE);
	loopinfo.lo_name[LO_NAME_SIZE - 1] = 0;
	loopinfo.lo_offset = 0;

#ifdef MCL_FUTURE  
	/*
	 * Oh-oh, sensitive data coming up. Better lock into memory to prevent
	 * passwd etc being swapped out and left somewhere on disk.
	 */
  
	  if(mlockall(MCL_CURRENT|MCL_FUTURE)) {
		  log_message("CRITICAL Couldn't lock into memory! %s (memlock)", strerror(errno));
		  return 1;
	  }
#endif

	if (ioctl(fd, LOOP_SET_FD, ffd) < 0) {
		close(fd);
		close(ffd);
		return 1;
	}

	if (ioctl(fd, LOOP_SET_STATUS, &loopinfo) < 0) {
		(void) ioctl (fd, LOOP_CLR_FD, 0);
		close(fd);
		close(ffd);
		return 1;
	}

	close(fd);
	close(ffd);
	return 0;
}


char* find_free_loop()
{
	struct loop_info loopinfo;
        int i;
        for (i=0; i<256; i++) {
                int fd;
		char ldev[100];
		sprintf(ldev, "/dev/loop%d", i);
                ensure_dev_exists(ldev);
                fd = open(ldev, O_RDONLY);
                if (!ioctl(fd, LOOP_GET_STATUS, &loopinfo)) {
                        close(fd);
                        continue;
                }
                if (errno == ENXIO) {
                        log_message("%s is available", ldev);
                        close(fd);
                        return strdup(ldev);
                } else {
                        log_perror("LOOP_GET_STATUS(unexpected error)");
                        close(fd);
                        continue;
                }
        }
        return NULL;
}

void
del_loop(char * loopdev)
{
	int fd;

        if (!loopdev)
                return;

	if ((fd = open (loopdev, O_RDONLY)) < 0)
		return;

	if (ioctl (fd, LOOP_CLR_FD, 0) < 0)
		return;
  
	close (fd);
}

int
lomount(char *loopfile, char *where, char **dev, int compressed)
{
  
	long int flag;
        char * loopdev;

	flag = MS_MGC_VAL;
	flag |= MS_RDONLY;

	my_insmod("loop", ANY_DRIVER_TYPE, "max_loop=256", 1);
	if (compressed) {
	    my_insmod("squashfs", ANY_DRIVER_TYPE, NULL, 1);
	}

        if (!(loopdev = find_free_loop())) {
		log_message("could not find a free loop");
		return 1;
        }
        if (dev)
                *dev = loopdev;

	if (set_loop(loopdev, loopfile)) {
		log_message("set_loop failed on %s (%s)", loopdev, strerror(errno));
		return 1;
	}
  
	if (my_mount(loopdev, where, compressed ? "squashfs" : "iso9660", 0)) {
		del_loop(loopdev);
		return 1;
	}

	log_message("lomount succeeded for %s on %s", loopfile, where);
	return 0;
}


