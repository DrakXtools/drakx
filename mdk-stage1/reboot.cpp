/*
 * Per Øyvind Karlsen <proyvind@moondrake.org>
 *
 * Copyright 2013 Moondrake
 *
 * This software may be freely redistributed under the terms of the GNU
 * public license.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 *
 */

#include <cstdlib>
#include <unistd.h>
#include <cstdio>
#include <cstring>
#include <cstdint>
#include <fcntl.h>
#include <sys/mount.h>
#include <csignal>
#include <sys/select.h>
#include <sys/ioctl.h>
#include <linux/reboot.h>

#include <sys/syscall.h>

#include "params.h"
#include "stage1.h"

static inline long reboot(uint32_t command)
{
	return (long) syscall(__NR_reboot, LINUX_REBOOT_MAGIC1, LINUX_REBOOT_MAGIC2, command, 0);
}

#define LOOP_CLR_FD	0x4C01

static void del_loops(void) 
{
        char loopdev[] = "/dev/loop0";
        char chloopdev[] = "/dev/chloop0";
        for (int i=0; i<8; i++) {
                int fd;
                loopdev[9] = '0' + i;
                fd = open(loopdev, O_RDONLY, 0);
                if (fd > 0) {
                        if (!ioctl(fd, LOOP_CLR_FD, 0))
                                printf("\t%s\n", loopdev);
                        close(fd);
                }
                chloopdev[11] = '0' + i;
                fd = open(chloopdev, O_RDONLY, 0);
                if (fd > 0) {
                        if (!ioctl(fd, LOOP_CLR_FD, 0))
                                printf("\t%s\n", chloopdev);
                        close(fd);
                }
        }
}

struct filesystem
{
	char * dev;
	char * name;
	char * fs;
	bool mounted;
};

/* attempt to unmount all filesystems in /proc/mounts */
static void unmount_filesystems(void)
{
	int fd, size;
	char buf[65535];			/* this should be big enough */
	char *p;
	struct filesystem fs[500];
	int numfs = 0;
	int i, nb;

	printf("unmounting filesystems...\n"); 

	fd = open("/proc/mounts", O_RDONLY, 0);
	if (fd < 1) {
		printf("E: failed to open /proc/mounts");
		sleep(2);
		return;
	}

	size = read(fd, buf, sizeof(buf) - 1);
	buf[size] = '\0';

	close(fd);

	p = buf;
	while (*p) {
		fs[numfs].mounted = true;
		fs[numfs].dev = p;
		while (*p != ' ') p++;
		*p++ = '\0';
		fs[numfs].name = p;
		while (*p != ' ') p++;
		*p++ = '\0';
		fs[numfs].fs = p;
		while (*p != ' ') p++;
		*p++ = '\0';
		while (*p != '\n') p++;
		p++;
		if (strcmp(fs[numfs].name, "/")
                    && !strstr(fs[numfs].dev, "ram")
                    && strcmp(fs[numfs].name, "/dev")
                    && strcmp(fs[numfs].name, "/sys")
                    && strncmp(fs[numfs].name, "/proc", 5))
                        numfs++;
	}

	/* Pixel's ultra-optimized sorting algorithm:
	   multiple passes trying to umount everything until nothing moves
	   anymore (a.k.a holy shotgun method) */
	do {
		nb = 0;
		for (i = 0; i < numfs; i++) {
			/*printf("trying with %s\n", fs[i].name);*/
                        del_loops();
			if (fs[i].mounted && umount(fs[i].name) == 0) { 
				printf("\t%s\n", fs[i].name);
				fs[i].mounted = false;
				nb++;
			}
		}
	} while (nb);

	for (i = nb = 0; i < numfs; i++)
		if (fs[i].mounted) {
			printf("\tumount failed: %s\n", fs[i].name);
			if (strncmp(fs[i].fs, "ext", 3) == 0) nb++; /* don't count non-ext* umount failed */
		}


	if (nb) {
		printf("failed to umount some filesystems\n");
                select(0, NULL, NULL, NULL, NULL);
	}
}

int reboot_main(int argc, char *argv[])
{
	reboot(LINUX_REBOOT_CMD_CAD_ON);

	for (uint8_t i=0; i<50; i++)
		printf("\n");  /* cleanup startkde messages */

	if (get_param(MODE_TESTING))
		return 0;

	sync(); sync();
	sleep(2);

	printf("sending termination signals...");
	kill(-1, 15);
	sleep(2);
	printf("done\n");

	printf("sending kill signals...");
	kill(-1, 9);
	sleep(2);
	printf("done\n");

	unmount_filesystems();

	sync(); sync();

	printf("you may safely reboot or halt your system\n");

        select(0, NULL, NULL, NULL, NULL);
	return 0;
}
