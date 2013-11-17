/*
 * Guillaume Cottenceau (gc@mandriva.com)
 *
 * Copyright 2001 Mandriva
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

#include "rescue-gui.h"
#include "config-stage1.h"
#include "frontend.h"
#include "utils.h"
#include "params.h"
#include "lomount.h"
#include "probing.h"

#if defined(__i386__) || defined(__x86_64__)
#define ENABLE_RESCUE_MS_BOOT 1
#endif

/* pause() already exists and causes the invoking process to sleep
   until a signal is received */
static void PAUSE(void) {
  unsigned char t;
  fflush(stdout);
  read(0, &t, 1);
}

int rescue_gui_main(int argc __attribute__ ((unused)), char *argv[] __attribute__ ((unused)), char *env[])
{
	enum return_type results;

	const char install_bootloader[] = "Re-install Boot Loader";
#if ENABLE_RESCUE_MS_BOOT
	const char restore_ms_boot[] = "Restore Windows Boot Loader";
#endif
	const char mount_parts[] = "Mount your partitions under /mnt";
	const char go_to_console[] = "Go to console";
	const char reboot_[] = "Reboot";
	const char doc[] = "Doc: what's addressed by this Rescue?";

	const char upgrade[] = "Upgrade to New Version";
	const char rootpass[] = "Reset Root Password";
	const char userpass[] = "Reset User Password";
	const char factory[] = "Reset to Factory Defaults";
	const char backup[] = "Backup User Files";
	const char restore[] = "Restore User Files from Backup";
	const char badblocks[] = "Test Key for Badblocks";

	const char * actions_default[] = { install_bootloader,
#if ENABLE_RESCUE_MS_BOOT
			             restore_ms_boot,
#endif
			             mount_parts, go_to_console, reboot_, doc, NULL };
	const char * actions_flash_rescue[] = { rootpass, userpass, factory, backup, restore,
					  badblocks, go_to_console, reboot_, NULL };
	const char * actions_flash_upgrade[] = { upgrade, go_to_console, reboot_, NULL };


	const char * flash_mode;
	const char ** actions;
	char * choice = NULL;

	setenv("PATH", "/usr/bin:/bin:/sbin:/usr/sbin:/mnt/sbin:/mnt/usr/sbin:/mnt/bin:/mnt/usr/bin", 1);
	setenv("LD_LIBRARY_PATH","/lib:/usr/lib:/mnt/lib:/mnt/usr/lib"
#if defined(__x86_64__) || defined(__ppc64__)
			":/lib64:/usr/lib64:/mnt/lib64:/mnt/usr/lib64"
#endif
			, 1);
	setenv("HOME", "/", 0);
	setenv("TERM", "linux", 1);
	setenv("TERMINFO", "/etc/terminfo", 1);

	process_cmdline();
	flash_mode = get_param_valued("flash");
	actions = !flash_mode ?
	    actions_default :
	    streq(flash_mode, "upgrade") ? actions_flash_upgrade : actions_flash_rescue;

	init_frontend("Welcome to " DISTRIB_NAME " Rescue (" DISTRIB_VERSION ") " __DATE__ " " __TIME__);

        /* load usb interface as soon as possible, helps usb keyboard & mouse  */
	probe_that_type(USB_CONTROLLERS, BUS_USB);
	handle_hid();

	do {
		int pid;
		const char * child_argv[4] = {NULL, NULL, NULL, NULL};

		results = ask_from_list("Please choose the desired action.", actions, &choice);

		if (ptr_begins_static_str(choice, install_bootloader))
			child_argv[0] = "/usr/bin/install_bootloader";
#if ENABLE_RESCUE_MS_BOOT
		else if (ptr_begins_static_str(choice, restore_ms_boot))
			child_argv[0] = "/usr/bin/restore_ms_boot";
#endif
		else if (ptr_begins_static_str(choice, mount_parts))
			child_argv[0] = "/usr/bin/guessmounts";
		else if (ptr_begins_static_str(choice, reboot_)) {
			finish_frontend();
                        sync();
			printf("rebooting system\n");
			/* FIXME: issues unmounting some (less critical at least) mount points */
			child_argv[0] = "/sbin/reboot";
			child_argv[1] = "-d";
			child_argv[2] = "2";
		}
		else if (ptr_begins_static_str(choice, doc))
			child_argv[0] = "/usr/bin/rescue-doc";
		else if (ptr_begins_static_str(choice, go_to_console)) {
			child_argv[0] = "/bin/sh";
			child_argv[1] = "--login";
		}
		/* Mandriva Flash entries */
		else if (ptr_begins_static_str(choice, rootpass))
			child_argv[0] = "/usr/bin/reset_rootpass";
		else if (ptr_begins_static_str(choice, userpass))
			child_argv[0] = "/usr/bin/reset_userpass";
		else if (ptr_begins_static_str(choice, factory))
			child_argv[0] = "/usr/bin/clear_systemloop";
		else if (ptr_begins_static_str(choice, backup))
			child_argv[0] = "/usr/bin/backup_systemloop";
		else if (ptr_begins_static_str(choice, restore))
			child_argv[0] = "/usr/bin/restore_systemloop";
		else if (ptr_begins_static_str(choice, badblocks))
			child_argv[0] = "/usr/bin/test_badblocks";
		else if (ptr_begins_static_str(choice, upgrade))
			child_argv[0] = "/usr/bin/upgrade";

		if (child_argv[0]) {
			int wait_status;
			suspend_to_console();
			if (!(pid = fork())) {

				execve(child_argv[0], (char* const*)child_argv, env);

				printf("Can't execute binary (%s)\n<press Enter>\n", child_argv[0]);
				PAUSE();

				return 33;
			}
			while (wait4(-1, &wait_status, 0, NULL) != pid) {};
			printf("<press Enter to return to Rescue menu>");
			PAUSE();
			resume_from_suspend();
			if (!WIFEXITED(wait_status) || WEXITSTATUS(wait_status) != 0) {
				error_message("Program exited abnormally (return code %d).", WEXITSTATUS(wait_status));
				if (WIFSIGNALED(wait_status))
					error_message("(received signal %d)", WTERMSIG(wait_status));
			}
		}

	} while (results == RETURN_OK);

	finish_frontend();
	printf("Bye.\n");
	
	return 0;
}
