/*
 * Guillaume Cottenceau (gc@mandrakesoft.com)
 *
 * Copyright 2001 Mandrakesoft
 *
 * This software is covered by the GPL license.
 *
 * This software may be freely redistributed under the terms of the GNU
 * public license.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 *
 *
 * This little program replaces usual sash and insmod.static based script
 * from mkinitrd (that insmod modules, plus possibly mount a partition and
 * losetup a loopback-based / on the partition).
 *
 *
 * On my machine:
 *   gzipped sash + insmod.static         502491 bytes
 *   gzipped <this-program>                14243 bytes
 *
 * There will be room for linux-2.4 and many modules, now. Cool.
 *
 */

#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <sys/mount.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/ioctl.h>
#include <signal.h>

#include "insmod.h"

int quiet = 0;

void vlog_message(const char * s, va_list args)
{
	vprintf(s, args);
	printf("\n");
}

void log_perror(char *msg)
{
	perror(msg);
}


static void fatal_error(char *msg)
{
	printf("[] E: %s\n[] giving hand to kernel.\n", msg);
        exit(-1);
}

static void warning(char *msg)
{
	printf("[] W: %s\n", msg);
}

static void parse_parms(const char * parm, char ** parm1, char ** parm2, char ** parm3)
{
	char * ptr;
	
	ptr = strchr(parm, '\n');
	if (!ptr)
		fatal_error("bad config file: no newline after parms");

	*parm1 = malloc(ptr-parm+1); /* yup, never freed :-) */
	memcpy(*parm1, parm, ptr-parm);
	(*parm1)[ptr-parm] = '\0';

	if (!parm2)
		return;

	*parm2 = strchr(*parm1, ' ');
	if (!*parm2)
		return;
	**parm2 = '\0';
	(*parm2)++;

	if (!parm3)
		return;

	*parm3 = strchr(*parm2, ' ');
	if (!*parm3)
		return;
	**parm3 = '\0';
	(*parm3)++;
}


static void insmod_(const char * parm)
{
	char * mod_name, * options;

	parse_parms(parm, &mod_name, &options, NULL);

#ifdef DEBUG
	printf("insmod %s options %s\n", mod_name, options);
#endif
	if (!quiet)
		printf("[] Loading module %s\n", mod_name);

	if (insmod_call(mod_name, options))
		perror("insmod failed");
}


static void mount_(const char * parm)
{
	char * dev, * location, * fs;
	unsigned long flags;
	char * opts = NULL;

	parse_parms(parm, &dev, &location, &fs);

#ifdef DEBUG
	printf("mounting %s on %s as type %s\n", dev, location, fs);
#endif
	if (!quiet)
		printf("[] Mounting device containing loopback root filesystem\n");

	flags = MS_MGC_VAL;

	if (!strcmp(fs, "vfat"))
		opts = "check=relaxed";

	if (mount(dev, location, fs, flags, opts))
		perror("mount failed");
}


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

static void set_loop_(const char * parm)
{
	struct loop_info loopinfo;
	int fd, ffd;
	char * device, * file;

	parse_parms(parm, &device, &file, NULL);

#ifdef DEBUG
	printf("set_looping %s with %s\n", device, file);
#endif
	if (!quiet)
		printf("[] Setting up loopback file %s\n", file);

	if ((ffd = open(file, O_RDWR)) < 0) {
		perror("set_loop, opening file in rw");
		exit(-1);
	}
  
	if ((fd = open(device, O_RDWR)) < 0) {
		perror("set_loop, opening loop device in rw");
		close(ffd);
		exit(-1);
	}

	memset(&loopinfo, 0, sizeof (loopinfo));
	strncpy(loopinfo.lo_name, file, LO_NAME_SIZE);
	loopinfo.lo_name[LO_NAME_SIZE - 1] = 0;
	loopinfo.lo_offset = 0;

	if (ioctl(fd, LOOP_SET_FD, ffd) < 0) {
		close(fd);
		close(ffd);
		perror("LOOP_SET_FD");
		exit(-1);
	}

	if (ioctl(fd, LOOP_SET_STATUS, &loopinfo) < 0) {
		(void) ioctl (fd, LOOP_CLR_FD, 0);
		close(fd);
		close(ffd);
		perror("LOOP_SET_STATUS");
		exit(-1);
	}

	close(fd);
	close(ffd);
}


#define MD_MAJOR 9
#define RAID_AUTORUN           _IO (MD_MAJOR, 0x14)
#include <linux/raid/md_u.h>

static void raidautorun_(const char * parm)
{
	char * device;
	int fd;

	parse_parms(parm, &device, NULL, NULL);

	if (!quiet)
		printf("[] Calling raid autorun for %s\n", device);
	
	fd = open(device, O_RDWR, 0);
	if (fd < 0) {
		printf("raidautorun: failed to open %s: %d\n", device, errno);
		return;
	}
	
	if (ioctl(fd, RAID_AUTORUN, 0)) {
		printf("raidautorun: RAID_AUTORUN failed: %d\n", errno);
	}
	
	close(fd);
}

static int handle_command(char ** ptr, char * cmd_name, void (*cmd_func)(const char * parm))
{
	if (!strncmp(*ptr, cmd_name, strlen(cmd_name))) {
		*ptr = strchr(*ptr, '\n');
		if (!*ptr)
			fatal_error("Bad config file: no newline after command");
		(*ptr)++;
		cmd_func(*ptr);
		*ptr = strchr(*ptr, '\n');
		if (!*ptr)
			exit(0);
		(*ptr)++;
		return 1;
	}
	return 0;
}


int main(int argc, char **argv)
{
	int fd_conf, i;
	char buf[5000];
	char * ptr;

	if (strstr(argv[0], "modprobe"))
		exit(0);

	if (mount("/proc", "/loopfs", "proc", 0, NULL))
		printf("[] couldn't mount proc filesystem\n");
	else {
		int fd_cmdline = open("/loopfs/cmdline", O_RDONLY);
		if (fd_cmdline > 0) {
			i = read(fd_cmdline, buf, sizeof(buf));
			if (i == -1)
				warning("could not read cmdline");
			else {
				buf[i] = '\0';
				if (strstr(buf, "quiet"))
					quiet = 1;
			}
			close(fd_cmdline);
		}
		umount("/loopfs");
	}

	if (!quiet)
		printf("[] initrd_helper v" VERSION "\n");

	if ((fd_conf = open("/mkinitrd_helper.conf", O_RDONLY)) < 0)
		fatal_error("could not open mkinitrd_helper config file");
	
	i = read(fd_conf, buf, sizeof(buf));
	if (i == -1)
		fatal_error("could not read mkinitrd_helper config file");
	buf[i] = '\0';
	close(fd_conf);

	ptr = buf;

	while (*ptr)
		if (!(handle_command(&ptr, "insmod", insmod_) +
		      handle_command(&ptr, "mount", mount_) +
		      handle_command(&ptr, "raidautorun", raidautorun_) +
		      handle_command(&ptr, "set_loop", set_loop_)))
			warning("unkown command (trying to continue)");

	return 0;
}
