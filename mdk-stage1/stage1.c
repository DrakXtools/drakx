/*
 * Guillaume Cottenceau (was gc@mandrakesoft.com)
 *
 * Copyright 2000-2004 Mandrakesoft
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

/*
 * Portions from Erik Troan (ewt@redhat.com)
 *
 * Copyright 1996 Red Hat Software 
 *
 */

#include <stdlib.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <stdio.h>
#include <sys/ioctl.h>
#include <sys/mount.h>
#include <string.h>
#include <errno.h>
#include <ctype.h>
#include <stdarg.h>
#include <signal.h>
#include <linux/unistd.h>

#include "stage1.h"

#include "log.h"
#include "probing.h"
#include "frontend.h"
#include "modules.h"
#include "tools.h"
#include "utils.h"
#include "automatic.h"
#include "mount.h"
#include "thirdparty.h"

#ifdef ENABLE_PCMCIA
#include "pcmcia/pcmcia.h"
#endif

#ifndef DISABLE_CDROM
#include "cdrom.h"
#endif

#ifndef DISABLE_NETWORK
#include "network.h"
#endif

#ifndef DISABLE_DISK
#include "disk.h"
#endif


/************************************************************
 * globals */



void fatal_error(char *msg)
{
	printf("FATAL ERROR IN STAGE1: %s\n\nI can't recover from this.\nYou may reboot your system.\n", msg);
	while (1);
}


/************************************************************
 * special frontend functs
 * (the principle is to not pollute frontend code with stage1-specific stuff) */

void stg1_error_message(char *msg, ...)
{
	va_list args;
	va_start(args, msg);
	unset_automatic();
	verror_message(msg, args);
	va_end(args);
}

void stg1_fatal_message(char *msg, ...)
{
	va_list args;
	va_start(args, msg);
	unset_automatic();
	verror_message(msg, args);
	va_end(args);
        exit(1);
}

void stg1_info_message(char *msg, ...)
{
	va_list args;
	va_start(args, msg);
	if (IS_AUTOMATIC) {
		vlog_message(msg, args);
		return;
	}
	vinfo_message(msg, args);
	va_end(args);
}


#ifdef SPAWN_SHELL
static pid_t shell_pid = 0;

/************************************************************
 * spawns a shell on console #2 */
static void spawn_shell(void)
{
	int fd;
	char * shell_name[] = { "/sbin/sh", NULL };

	log_message("spawning a shell");

	if (!IS_TESTING) {
		fd = open("/dev/tty2", O_RDWR);
		if (fd == -1) {
			log_message("cannot open /dev/tty2 -- no shell will be provided");
			return;
		}
		else if (access(shell_name[0], X_OK)) {
			log_message("cannot open shell - %s doesn't exist", shell_name[0]);
			return;
		}
		
		if (!(shell_pid = fork())) {
			dup2(fd, 0);
			dup2(fd, 1);
			dup2(fd, 2);
			
			close(fd);
			setsid();
			if (ioctl(0, TIOCSCTTY, NULL))
				log_perror("could not set new controlling tty");

			execv(shell_name[0], shell_name);
			log_message("execve of %s failed: %s", shell_name[0], strerror(errno));
			exit(-1);
		}
		
		close(fd);
	}
}
#endif

#ifdef SPAWN_INTERACTIVE
char * interactive_fifo = "/tmp/stage1-fifo";
static pid_t interactive_pid = 0;

/* spawns my small interactive on console #6 */
static void spawn_interactive(void)
{
	int fd;
	char * dev = "/dev/tty6";

	printf("spawning my interactive on %s\n", dev);

	if (!IS_TESTING) {
		fd = open(dev, O_RDWR);
		if (fd == -1) {
			printf("cannot open %s -- no interactive\n", dev);
			return;
		}

		if (mkfifo(interactive_fifo, O_RDWR)) {
			printf("cannot create fifo -- no interactive\n");
			return;
		}
		
		if (!(interactive_pid = fork())) {
			int fif_out;

			dup2(fd, 0);
			dup2(fd, 1);
			dup2(fd, 2);
			
			close(fd);
			setsid();
			if (ioctl(0, TIOCSCTTY, NULL))
				perror("could not set new controlling tty");

			fif_out = open(interactive_fifo, O_WRONLY);
			printf("Please enter your command (availables: [+,-] [rescue]).\n");
				
			while (1) {
				char s[50];
				int i = 0;
				printf("? ");
				fflush(stdout);
				read(0, &(s[i++]), 1);
				fcntl(0, F_SETFL, O_NONBLOCK);
				while (read(0, &(s[i++]), 1) > 0 && i < sizeof(s));
				fcntl(0, F_SETFL, 0);
				write(fif_out, s, i-2);
				printf("Ok.\n");
			}
		}
		
		close(fd);
	}
}
#endif


#ifdef ENABLE_PCMCIA
static void handle_pcmcia(void)
{
        char * pcmcia_adapter;
	if (kernel_version() == 2) {
		stg1_error_message("We now use kernel pcmcia support and this won't work with a 2.2 kernel.");
		return;
	}

	pcmcia_adapter = pcmcia_probe();
	if (!pcmcia_adapter) {
		log_message("no pcmcia adapter found");
		return;
	}
	my_insmod("pcmcia_core", ANY_DRIVER_TYPE, NULL, 0);
	my_insmod(pcmcia_adapter, ANY_DRIVER_TYPE, NULL, 0);
	/* ds is an alias for pcmcia in recent 2.6 kernels
           but we don't have modules.alias in install, so try to load both */
	my_insmod("ds", ANY_DRIVER_TYPE, NULL, 0);
	my_insmod("pcmcia", ANY_DRIVER_TYPE, NULL, 0);
	
        /* setup a dynamic resource database for non statically mapped PCMCIA sockets */
	pcmcia_socket_startup(-1);

	add_to_env("PCMCIA", pcmcia_adapter);
}
#endif


/************************************************************
 */

static void method_select_and_prepare(void)
{
	enum return_type results;
	char * choice;
	char * means[10], * means_auto[10];
	int i;

#ifndef DISABLE_DISK
	char * disk_install = "Hard disk"; char * disk_install_auto = "disk";
#endif
#ifndef DISABLE_CDROM
	char * cdrom_install = "CDROM drive"; char * cdrom_install_auto = "cdrom";
#endif
#ifndef DISABLE_NETWORK
	char * network_nfs_install = "NFS server"; char * network_nfs_install_auto = "nfs";
	char * network_ftp_install = "FTP server"; char * network_ftp_install_auto = "ftp";
	char * network_http_install = "HTTP server"; char * network_http_install_auto = "http";
#ifndef DISABLE_KA
	char * network_ka_install = "KA server"; char * network_ka_install_auto = "ka";
#endif
#endif
	char * thirdparty_install = "Load third party modules"; char * thirdparty_install_auto = "thirdparty";

	i = 0;
#ifndef DISABLE_NETWORK
	means[i] = network_nfs_install; means_auto[i++] = network_nfs_install_auto;
	means[i] = network_ftp_install; means_auto[i++] = network_ftp_install_auto;
	means[i] = network_http_install; means_auto[i++] = network_http_install_auto;
#ifndef DISABLE_KA
	means[i] = network_ka_install; means_auto[i++] = network_ka_install_auto;
#endif
#endif
#ifndef DISABLE_CDROM
	means[i] = cdrom_install; means_auto[i++] = cdrom_install_auto;
#endif
#ifndef DISABLE_DISK
	means[i] = disk_install; means_auto[i++] = disk_install_auto;
#endif
	means[i] = thirdparty_install; means_auto[i++] = thirdparty_install_auto;
	means[i] = NULL;

	unlink(IMAGE_LOCATION);

	results = ask_from_list_auto("Please choose the installation method.", means, &choice, "method", means_auto);

	if (results != RETURN_OK)
		return method_select_and_prepare();

#ifndef DISABLE_CDROM
	if (!strcmp(choice, cdrom_install))
		results = cdrom_prepare();
#endif
        
#ifndef DISABLE_DISK
	if (!strcmp(choice, disk_install))
		results = disk_prepare();
#endif
	
#ifndef DISABLE_NETWORK
	if (!strcmp(choice, network_nfs_install))
		results = nfs_prepare();

	if (!strcmp(choice, network_ftp_install))
		results = ftp_prepare();
	
	if (!strcmp(choice, network_http_install))
		results = http_prepare();

#ifndef DISABLE_KA
	if (!strcmp(choice, network_ka_install))
		results = ka_prepare();
#endif
#endif

	if (!strcmp(choice, thirdparty_install)) {
		thirdparty_load_modules();
		return method_select_and_prepare();
        }

	if (results != RETURN_OK)
		return method_select_and_prepare();

        /* try to find third party modules on the install media */
        thirdparty_load_media_modules();
}

static enum return_type create_initial_fs_symlinks(char* symlinks)
{
        FILE *f;
        char buf[5000];

        if (scall(!(f = fopen(symlinks, "rb")), "fopen"))
                return RETURN_ERROR;
        while (fgets(buf, sizeof(buf), f)) {
                char oldpath[500], newpath[500];
                buf[strlen(buf)-1] = '\0';  // trim \n
                if (sscanf(buf, "%s %s", oldpath, newpath) != 2) {
                        sprintf(oldpath, "%s%s", STAGE2_LOCATION, buf);
			sprintf(newpath, "%s", buf);
                }
		recursiveRemove_if_it_exists(newpath);
                log_message("creating symlink %s -> %s", oldpath, newpath);
                if (scall(symlink(oldpath, newpath), "symlink"))
                        return RETURN_ERROR;
        }
        fclose(f);
        return RETURN_OK;
}

void finish_preparing(void)
{
	recursiveRemove("/init");

	if (create_initial_fs_symlinks(STAGE2_LOCATION "/usr/share/symlinks") != RETURN_OK)
		stg1_fatal_message("Fatal error finishing initialization.");

	/* /tmp/syslog is used by the second init, so it must be copied now, not in stage2 */
	/* we remove it to ensure the old one is not copied over it in stage2 */

#ifdef SPAWN_SHELL
	if (shell_pid != 0) {
		int fd;
		kill(shell_pid, 9);
		fd = open("/dev/tty2", O_RDWR);
		write(fd, "Killed\n", 7);
		close(fd);
        }
#endif
}

int main(int argc __attribute__ ((unused)), char **argv __attribute__ ((unused)), char **env)
{
#ifdef ENABLE_NETWORK_STANDALONE
	open_log();
	init_frontend("");

	unlink("/etc/resolv.conf"); /* otherwise it is read-only */
	set_param(MODE_AUTOMATIC);
	grab_automatic_params("network:dhcp");

	intf_select_and_up();
	finish_frontend();
	return 0;
#else
	if (getenv("DEBUGSTAGE1")) {
		set_param(MODE_DEBUGSTAGE1);
		set_param(MODE_TESTING);
        }

#ifdef SPAWN_INTERACTIVE
	spawn_interactive();
#endif

	open_log();
	log_message("welcome to the " DISTRIB_NAME " install (mdk-stage1, version " DISTRIB_VERSION " built " __DATE__ " " __TIME__")");
	process_cmdline();
#ifdef SPAWN_SHELL
	spawn_shell();
#endif
	init_modules_insmoding();
	init_frontend("Welcome to " DISTRIB_DESCR ", " __DATE__ " " __TIME__);

        /* load usb interface as soon as possible, helps usb mouse detection in stage2 */
	probe_that_type(USB_CONTROLLERS, BUS_USB);

	if (IS_THIRDPARTY)
		thirdparty_load_modules();

#ifdef ENABLE_PCMCIA
	if (!IS_NOAUTO)
		handle_pcmcia();
#endif
        
	if (IS_CHANGEDISK)
		stg1_info_message("You are starting the installation with an alternate booting method. "
				  "Please change your disk, and insert the Installation disk.");

	if (IS_RESCUE && total_memory() < MEM_LIMIT_RESCUE) {
		stg1_error_message("You are starting the rescue with a low memory configuration. "
				   "Our experience shows that your system may crash at any point "
				   "or lock up for no apparent reason. Continue at "
				   "your own risk. Alternatively, you may reboot your system now.");
	}

        method_select_and_prepare();

	thirdparty_destroy();

	if (access(STAGE2_LOCATION, R_OK) != 0)
		if (symlink(IMAGE_LOCATION_REL "/" LIVE_LOCATION_REL, STAGE2_LOCATION) != 0)
			log_perror("symlink from " IMAGE_LOCATION_REL "/" LIVE_LOCATION_REL " to " STAGE2_LOCATION " failed");

#ifdef SPAWN_INTERACTIVE
	if (interactive_pid != 0)
		kill(interactive_pid, 9);
#endif

	finish_preparing();

	finish_frontend();
	close_log();

	if (IS_RESCUE)
		return 66; /* ask init to exec new init */
	else
		return 0x35; /* ask init to run stage2 binary */
#endif
}
