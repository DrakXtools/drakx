/*
 * Guillaume Cottenceau (gc@mandrakesoft.com)
 *
 * Copyright 2001 Mandrakesoft
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
#include "utils.h"

#if defined(__i386__) || defined(__x86_64__)
#define ENABLE_RESCUE_MS_BOOT 1
#endif

char * env[] = {
	"PATH=/usr/bin:/bin:/sbin:/usr/sbin:/mnt/sbin:/mnt/usr/sbin:/mnt/bin:/mnt/usr/bin",
	"LD_LIBRARY_PATH=/lib:/usr/lib:/mnt/lib:/mnt/usr/lib:/usr/X11R6/lib:/mnt/usr/X11R6/lib"
#if defined(__x86_64__) || defined(__ppc64__)
	":/lib64:/usr/lib64:/usr/X11R6/lib64:/mnt/lib64:/mnt/usr/lib64:/mnt/usr/X11R6/lib64"
#endif
	,
	"HOME=/",
	"TERM=linux",
	"TERMINFO=/etc/terminfo",
	NULL
};

/* pause() already exists and causes the invoking process to sleep
   until a signal is received */
static void PAUSE(void) {
  unsigned char t;
  fflush(stdout);
  read(0, &t, 1);
}


/* ------ UUURGH this is duplicated from `init.c', don't edit here........ */
void fatal_error(char *msg)
{
	printf("FATAL ERROR IN RESCUE: %s\n\nI can't recover from this.\nYou may reboot your system.\n", msg);
	while (1);
}

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
struct filesystem { char * dev; char * name; char * fs; int mounted; };
void unmount_filesystems(void)
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
		printf("ERROR: failed to open /proc/mounts");
		sleep(2);
		return;
	}

	size = read(fd, buf, sizeof(buf) - 1);
	buf[size] = '\0';

	close(fd);

	p = buf;
	while (*p) {
		fs[numfs].mounted = 1;
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
		if (strcmp(fs[numfs].name, "/") != 0) numfs++; /* skip if root, no need to take initrd root in account */
	}

	/* Pixel's ultra-optimized sorting algorithm:
	   multiple passes trying to umount everything until nothing moves
	   anymore (a.k.a holy shotgun method) */
	do {
		nb = 0;
		for (i = 0; i < numfs; i++) {
			/*printf("trying with %s\n", fs[i].name);*/
			if (fs[i].mounted && umount(fs[i].name) == 0) { 
				if (strncmp(fs[i].dev + sizeof("/dev/") - 1, "loop",
					    sizeof("loop") - 1) == 0)
					del_loop(fs[i].dev);
				
				printf("\t%s\n", fs[i].name);
				fs[i].mounted = 0;
				nb++;
			}
		}
	} while (nb);
	
	for (i = nb = 0; i < numfs; i++)
		if (fs[i].mounted) {
			printf("\t%s umount failed\n", fs[i].name);
			if (strcmp(fs[i].fs, "ext2") == 0) nb++; /* don't count not-ext2 umount failed */
		}
	
	if (nb) {
		printf("failed to umount some filesystems\n");
		while (1);
	}
}
/* ------ UUURGH -- end */


/* ------ UUURGH -- this is dirrrrrttttyyyyyy */
void probe_that_type(void) {}
void exit_bootsplash(void) {}


int main(int argc __attribute__ ((unused)), char **argv __attribute__ ((unused)))
{
	enum return_type results;

	char install_bootloader[] = "Re-install Boot Loader";
#if ENABLE_RESCUE_MS_BOOT
	char restore_ms_boot[] = "Restore Windows Boot Loader";
#endif
	char mount_parts[] = "Mount your partitions under /mnt";
	char go_to_console[] = "Go to console";
	char reboot_[] = "Reboot";
	char doc[] = "Doc: what's addressed by this Rescue?";

	char * actions[] = { install_bootloader,
#if ENABLE_RESCUE_MS_BOOT
			     restore_ms_boot,
#endif
			     mount_parts, go_to_console, reboot_, doc, NULL };
	char * choice;

	init_frontend("Welcome to " DISTRIB_NAME " Rescue (" DISTRIB_VERSION ") " __DATE__ " " __TIME__);

	do {
		int pid;
		char * binary = NULL;

		choice = "";
		results = ask_from_list("Please choose the desired action.", actions, &choice);

		if (ptr_begins_static_str(choice, install_bootloader)) {
			binary = "/usr/bin/install_bootloader";
		}
#if ENABLE_RESCUE_MS_BOOT
		if (ptr_begins_static_str(choice, restore_ms_boot)) {
			binary = "/usr/bin/restore_ms_boot";
		}
#endif
		if (ptr_begins_static_str(choice, mount_parts)) {
			binary = "/usr/bin/guessmounts";
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
		if (ptr_begins_static_str(choice, doc)) {
			binary = "/usr/bin/rescue-doc";
		}

		if (binary) {
			int wait_status;
			suspend_to_console();
			if (!(pid = fork())) {

				char * child_argv[2];
				child_argv[0] = binary;
				child_argv[1] = NULL;

				execve(child_argv[0], child_argv, env);
				printf("Can't execute binary (%s)\n<press Enter>\n", binary);
				PAUSE();

				return 33;
			}
			while (wait4(-1, &wait_status, 0, NULL) != pid) {};
			printf("<press Enter to return to Rescue GUI>");
			PAUSE();
			resume_from_suspend();
			if (!WIFEXITED(wait_status) || WEXITSTATUS(wait_status) != 0) {
				error_message("Program exited abnormally (return code %d).", WEXITSTATUS(wait_status));
				if (WIFSIGNALED(wait_status))
					error_message("(received signal %d)", WTERMSIG(wait_status));
			}
		}

	} while (results == RETURN_OK && !ptr_begins_static_str(choice, go_to_console));

	finish_frontend();
	printf("Bye.\n");
	
	return 0;
}
