/*
 * Guillaume Cottenceau (gc@mandrakesoft.com)
 *
 * Copyright 2001-2007 Mandrakesoft
 *
 *
 * This software may be freely redistributed under the terms of the GNU
 * public license.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 *
 */

#include <stdlib.h>
#include <strings.h>
#define _USE_BSD
#include <sys/types.h>
#include <sys/time.h>
#include <sys/resource.h>
#include <sys/wait.h>
#include <unistd.h>
#include <string.h>
#include <stdio.h>
#include <sys/mount.h>
#include <fcntl.h>
#include <sys/ioctl.h>
#include <linux/unistd.h>
#include <sys/select.h>

#include "config-stage1.h"
#include "frontend.h"
#include "tools.h"

#ifndef LINE_MAX
#define LINE_MAX	2048
#endif

char * env[] = {
	"PATH=/usr/bin:/bin:/sbin:/usr/sbin:/mnt/sbin:/mnt/usr/sbin:/mnt/bin:/mnt/usr/bin",
	"LD_LIBRARY_PATH=/lib:/usr/lib:/mnt/lib:/mnt/usr/lib:/usr/X11R6/lib:/mnt/usr/X11R6/lib",
	"HOME=/",
	"TERM=linux",
	"TERMINFO=/etc/terminfo",
	NULL
};

/* pause() already exists and causes the invoking process to sleep
   until a signal is received */
static void PAUSE(void)
{
	unsigned char t;
	fflush(stdout);
	read(0, &t, 1);
}

/* this is duplicated from `init.c', don't edit here */
static inline _syscall3(int, reboot, int, magic, int, magic2, int, flag);

#define LOOP_CLR_FD	0x4C01

void del_loop(char *device) 
{
	int fd;
	if ((fd = open(device, O_RDONLY, 0)) < 0) {
		printf("del_loop open failed\n");
		return;
	}

	if (ioctl(fd, LOOP_CLR_FD, 0) < 0) {
		printf("del_loop ioctl failed");
		return;
	}

	close(fd);
}

struct filesystem {
	char * dev;
	char * name;
	char * fs;
	int mounted;
};

void unmount_filesystems(void)
{
	struct filesystem fs[500];
	int i, nb, fd, size, numfs = 0;
	char *buf, *p;
	
	printf("unmounting filesystems...\n"); 
	
	fd = open("/proc/mounts", O_RDONLY, 0);
	if (fd == -1) {
		printf("ERROR: failed to open /proc/mounts");
		sleep(2);
		return;
	}

	buf = (char *) malloc(LINE_MAX);
	if (buf == NULL) {
		printf("ERROR: not enough memory");
		sleep(2);
		return;
	}
	bzero(buf, LINE_MAX);
	size = read(fd, buf, LINE_MAX - 1);
	close(fd);

	p = buf;
	while (*p) {

		fs[numfs].mounted = 1;
		fs[numfs].dev = p;
		while (*p != ' ')
			p++;

		*p++ = '\0';
		fs[numfs].name = p;
		while (*p != ' ')
			p++;

		*p++ = '\0';
		fs[numfs].fs = p;
		while (*p != ' ')
			p++;

		*p++ = '\0';
		while (*p != '\n')
			p++;
		p++;
		if (strcmp(fs[numfs].name, "/") != 0)
			/* skip if root, no need to take initrd root
			   in account */
			numfs++;
	}

	/* multiple passes trying to umount everything */
	do {
		nb = 0;
		for (i = 0; i < numfs; i++) {
			if (fs[i].mounted && umount(fs[i].name) == 0) { 
				if (strncmp(fs[i].dev + sizeof("/dev/") - 1,
					    "loop", sizeof("loop") - 1) == 0)
					del_loop(fs[i].dev);
				
				printf("\t%s\n", fs[i].name);
				fs[i].mounted = 0;
				nb++;
			}
		}
	} while (nb);
	
	for (i = nb = 0; i < numfs; i++) {
		if (fs[i].mounted) {
			printf("\t%s umount failed\n", fs[i].name);
			if (strcmp(fs[i].fs, "ext2") == 0)
				 /* don't count not-ext2 umount failed */
				nb++;
		}
	}
	
	if (nb) {
		printf("failed to umount some filesystems\n");
		while (1);
	}
}

void probe_that_type(void) { }

int main(int argc __attribute__ ((unused)), char **argv __attribute__ ((unused)))
{
	enum return_type results;

	char rootpass[] = "Reset Root Password";
	char userpass[] = "Reset User Password";
	char factory[] = "Reset to Factory Defaults";
	char backup[] = "Backup User Files";
	char restore[] = "Restore User Files from Backup";
	char badblocks[] = "Test Key for Badblocks";
	char reboot_[] = "Reboot";

	char * actions[] = { rootpass, userpass, factory, backup, restore,
		badblocks, reboot_, NULL };
	char * choice;

	init_frontend("Welcome to " DISTRIB_NAME " Rescue ("
			DISTRIB_VERSION ") " __DATE__ " " __TIME__);

	do {
		int pid;
		char * binary = NULL;

		choice = "";
		results = ask_from_list("Please choose the desired action.",
				actions, &choice);

		if (ptr_begins_static_str(choice, rootpass)) {
			binary = "/usr/bin/reset_rootpass";
		}
		if (ptr_begins_static_str(choice, userpass)) {
			binary = "/usr/bin/reset_userpass";
		}
		if (ptr_begins_static_str(choice, factory)) {
			binary = "/usr/bin/clear_systemloop";
		}
		if (ptr_begins_static_str(choice, backup)) {
			binary = "/usr/bin/backup_systemloop";
		}
		if (ptr_begins_static_str(choice, restore)) {
			binary = "/usr/bin/restore_systemloop";
		}
		if (ptr_begins_static_str(choice, badblocks)) {
			binary = "/usr/bin/test_badblocks";
		}
		if (ptr_begins_static_str(choice, reboot_)) {
			finish_frontend();
                        sync(); sync();
                        sleep(2);
			unmount_filesystems();
                        sync(); sync();
			printf("rebooting system\n");
			sleep(2);
			reboot(0xfee1dead, 672274793, 0x01234567);
		}

		if (binary) {

			int wait_status;

			suspend_to_console();
			pid = fork();
			if (pid == -1) {	/* error forking */

				printf("Can't fork()\n");
				return 33;

			} else if (pid == 0) {	/* child */

				char * child_argv[2];
				child_argv[0] = binary;
				child_argv[1] = NULL;

				execve(child_argv[0], child_argv, env);
				printf("Can't execute binary (%s)\n<press Enter>\n", binary);
				PAUSE();

				return 33;
			} else {		/* parent */

				while (wait4(-1, &wait_status, 0, NULL) != pid)
					;

				printf("<press Enter to return to Rescue GUI>");
				PAUSE();
				resume_from_suspend();
				if (!WIFEXITED(wait_status) || WEXITSTATUS(wait_status) != 0) {
					error_message("Program exited abnormally (return code %d).",
							WEXITSTATUS(wait_status));
					if (WIFSIGNALED(wait_status))
						error_message("(received signal %d)",
								WTERMSIG(wait_status));
				}
			}
		}

	} while (results == RETURN_OK);

	finish_frontend();
	printf("Bye.\n");
	
	return 0;
}
